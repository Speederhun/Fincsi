import SwiftUI
import UIKit
import UserNotifications
import FincsiKit

@MainActor
@Observable
final class CookingTimers {
    private(set) var endDates: [Int: Date] = [:]
    private let recipeTitle: String
    private let prefix = UUID().uuidString

    init(recipeTitle: String) {
        self.recipeTitle = recipeTitle
    }

    func start(step: Int, minutes: Int) {
        let seconds = Double(max(1, minutes) * 60)
        endDates[step] = Date().addingTimeInterval(seconds)
        let center = UNUserNotificationCenter.current()
        let title = recipeTitle
        let identifier = "\(prefix)-\(step)"
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Lejárt az időzítő"
            content.body = "\(title): \(step + 1). lépés kész."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    func cancel(step: Int) {
        endDates[step] = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(prefix)-\(step)"])
    }

    func cancelAll() {
        let ids = endDates.keys.map { "\(prefix)-\($0)" }
        endDates.removeAll()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func isRunning(_ step: Int) -> Bool { endDates[step] != nil }
}

struct CookingView: View {
    let recipe: Recipe
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var timers: CookingTimers
    @State private var confirmExit = false

    init(recipe: Recipe, onFinished: @escaping () -> Void) {
        self.recipe = recipe
        self.onFinished = onFinished
        _timers = State(initialValue: CookingTimers(recipeTitle: recipe.title))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(page + 1), total: Double(max(1, recipe.steps.count)))
                    .padding(.horizontal)
                    .accessibilityHidden(true)
                TabView(selection: $page) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        stepPage(index: index, step: step).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                controls
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bezár") { confirmExit = true }
                }
            }
            .confirmationDialog("Kilépsz a főzésből?", isPresented: $confirmExit) {
                Button("Kilépés", role: .destructive) { dismiss() }
                Button("Maradok", role: .cancel) {}
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timers.cancelAll()
        }
    }

    private func stepPage(index: Int, step: RecipeStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(index + 1). lépés / \(recipe.steps.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.paprika)
                Text(step.text)
                    .font(.title2)
                    .fixedSize(horizontal: false, vertical: true)
                if let minutes = step.timerMinutes {
                    timerBox(index: index, minutes: minutes)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timerBox(index: Int, minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let end = timers.endDates[index] {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(end.timeIntervalSince(context.date).rounded(.up)))
                    HStack {
                        Image(systemName: remaining == 0 ? "bell.fill" : "timer")
                        Text(remaining == 0 ? "Letelt!" : clock(remaining))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Button("Leállít") { timers.cancel(step: index) }
                            .buttonStyle(.bordered)
                    }
                    .foregroundStyle(remaining == 0 ? Theme.bad : Theme.paprika)
                    .accessibilityElement(children: .combine)
                }
            } else {
                Button {
                    timers.start(step: index, minutes: minutes)
                } label: {
                    Label("\(minutes) perces időzítő indítása", systemImage: "timer")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func clock(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }

    private var controls: some View {
        HStack {
            Button {
                withAnimation { page = max(0, page - 1) }
            } label: {
                Label("Előző", systemImage: "chevron.left")
            }
            .disabled(page == 0)
            Spacer()
            if page >= recipe.steps.count - 1 {
                Button {
                    onFinished()
                    dismiss()
                } label: {
                    Label("Elkészült!", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    withAnimation { page = min(recipe.steps.count - 1, page + 1) }
                } label: {
                    Label("Következő", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
    }
}
