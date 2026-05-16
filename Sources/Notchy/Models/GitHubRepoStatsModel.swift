import Combine
import Foundation

@MainActor
final class GitHubRepoStatsModel: ObservableObject {
    @Published var repoName: String = "Notchy"
    @Published var repoURL: String = "https://github.com/Rorogogogo/Notchy"
    @Published var starsText: String = "1"

    private var repoSlug: String = "Rorogogogo/Notchy"
    private var refreshTimer: Timer?

    init() {
        loadBundledValues()
        startLiveRefresh()
    }

    private func loadBundledValues() {
        if let bundledRepo = bundledString(named: "github-repo"), !bundledRepo.isEmpty {
            repoName = bundledRepo
            repoSlug = bundledRepo
        }
        if let bundledURL = bundledString(named: "github-url"), !bundledURL.isEmpty {
            repoURL = bundledURL
        }
        if let bundledStars = bundledString(named: "github-stars"), !bundledStars.isEmpty {
            starsText = Self.formatStars(Int(bundledStars) ?? 0)
        }
    }

    private func startLiveRefresh() {
        Task { await fetchStars() }
        let timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchStars() }
        }
        timer.tolerance = 60
        refreshTimer = timer
    }

    private func fetchStars() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Notchy", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let count = json["stargazers_count"] as? Int else { return }
            starsText = Self.formatStars(count)
        } catch {
            // keep bundled fallback
        }
    }

    private func bundledString(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatStars(_ count: Int) -> String {
        if count >= 1000 {
            let value = Double(count) / 1000.0
            return String(format: "%.1fk", value)
        }
        return "\(count)"
    }
}
