import Foundation
import RiviuDiff

/// A demo file: its base text plus the edits that turn it into the head version.
nonisolated struct DemoFile {
    var path: String
    var status: ChangeStatus = .modified
    var base: String
    var edits: [(String, String)] = []
    var findings: [(match: String, side: DiffSide, title: String, body: String, severity: ReviewFinding.Severity)] = []

    var head: String {
        switch status {
        case .deleted:
            return ""
        case .added:
            return base
        case .modified:
            var text = base
            for (old, new) in edits {
                guard let range = text.range(of: old) else {
                    assertionFailure("Demo edit not found in \(path): \(old)")
                    continue
                }
                text.replaceSubrange(range, with: new)
            }
            return text
        }
    }
}

/// The text of the demo pull requests.
nonisolated enum DemoFiles {
    static let tokenStore = DemoFile(
        path: "Sources/Auth/TokenStore.swift",
        base: #"""
        import Foundation

        /// Stores and refreshes GitHub OAuth tokens for the signed-in account.
        actor TokenStore {
            struct Token: Codable, Sendable {
                var accessToken: String
                var refreshToken: String?
                var expiresAt: Date?

                var isExpired: Bool {
                    guard let expiresAt else { return false }
                    return expiresAt < Date()
                }
            }

            private let keychain: KeychainClient
            private let session: URLSession
            private var cached: Token?

            init(keychain: KeychainClient, session: URLSession = .shared) {
                self.keychain = keychain
                self.session = session
            }

            func currentToken() async throws -> Token {
                if let cached, !cached.isExpired {
                    return cached
                }
                let stored = try keychain.read(Token.self, account: "github")
                if stored.isExpired {
                    let refreshed = try await refresh(stored)
                    try keychain.write(refreshed, account: "github")
                    cached = refreshed
                    return refreshed
                }
                cached = stored
                return stored
            }

            private func refresh(_ token: Token) async throws -> Token {
                guard let refreshToken = token.refreshToken else {
                    throw AuthError.reauthenticationRequired
                }
                var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken, "grant_type": "refresh_token"])
                let (data, _) = try await session.data(for: request)
                let response = try JSONDecoder().decode(RefreshResponse.self, from: data)
                return Token(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
                )
            }

            func signOut() throws {
                cached = nil
                try keychain.delete(account: "github")
            }
        }

        enum AuthError: Error {
            case reauthenticationRequired
        }
        """#,
        edits: [
            ("    private var cached: Token?\n", "    private var cached: Token?\n    private var inflightRefresh: Task<Token, Error>?\n"),
            ("""
                    let refreshed = try await refresh(stored)
                    try keychain.write(refreshed, account: "github")
                    cached = refreshed
        """, """
                    let refreshed = try await refreshOnce(stored)
                    cached = refreshed
        """),
            ("    private func refresh(_ token: Token)", """
                /// Coalesces concurrent refreshes so only one network request is in flight.
                private func refreshOnce(_ token: Token) async throws -> Token {
                    if let inflightRefresh {
                        return try await inflightRefresh.value
                    }
                    let task = Task { try await refresh(token) }
                    inflightRefresh = task
                    defer { inflightRefresh = nil }
                    let refreshed = try await task.value
                    try keychain.write(refreshed, account: "github")
                    return refreshed
                }

                private func refresh(_ token: Token)
            """),
            ("        request.setValue(\"application/json\", forHTTPHeaderField: \"Accept\")\n",
             "        request.setValue(\"application/json\", forHTTPHeaderField: \"Accept\")\n        request.timeoutInterval = 15\n"),
            ("        cached = nil\n        try keychain", "        cached = nil\n        inflightRefresh?.cancel()\n        try keychain"),
            ("    case reauthenticationRequired\n", "    case reauthenticationRequired\n    case refreshFailed(statusCode: Int)\n"),
        ],
        findings: [
            ("defer { inflightRefresh = nil }", .head, "Concurrent callers can still double-refresh",
             "`inflightRefresh` is cleared by `defer` while the keychain write is still pending. A caller that arrives during the write starts a second refresh and invalidates the first token.",
             .high),
        ]
    )

    static let diffParser = DemoFile(
        path: "Sources/Review/DiffParser.swift",
        base: #"""
        import Foundation

        struct DiffHunk: Equatable {
            var oldStart: Int
            var oldCount: Int
            var newStart: Int
            var newCount: Int
            var lines: [DiffLine]
        }

        enum DiffLine: Equatable {
            case context(String)
            case added(String)
            case removed(String)
        }

        enum DiffParser {
            static func parse(_ patch: String) -> [DiffHunk] {
                var hunks: [DiffHunk] = []
                var current: DiffHunk?
                for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
                    let line = String(raw)
                    if line.hasPrefix("@@") {
                        if let current { hunks.append(current) }
                        current = parseHeader(line)
                        continue
                    }
                    guard current != nil else { continue }
                    switch line.first {
                    case "+": current?.lines.append(.added(String(line.dropFirst())))
                    case "-": current?.lines.append(.removed(String(line.dropFirst())))
                    default: current?.lines.append(.context(String(line.dropFirst())))
                    }
                }
                if let current { hunks.append(current) }
                return hunks
            }

            private static func parseHeader(_ header: String) -> DiffHunk? {
                // @@ -12,7 +12,9 @@
                let parts = header.split(separator: " ")
                guard parts.count >= 3 else { return nil }
                let old = parts[1].dropFirst().split(separator: ",")
                let new = parts[2].dropFirst().split(separator: ",")
                return DiffHunk(
                    oldStart: Int(old[0]) ?? 0,
                    oldCount: Int(old[1]) ?? 0,
                    newStart: Int(new[0]) ?? 0,
                    newCount: Int(new[1]) ?? 0,
                    lines: []
                )
            }
        }
        """#,
        edits: [
            ("struct DiffHunk: Equatable {", "struct DiffHunk: Equatable, Sendable {"),
            ("enum DiffLine: Equatable {", "enum DiffLine: Equatable, Sendable {"),
            ("            case \"-\": current?.lines.append(.removed(String(line.dropFirst())))\n",
             "            case \"-\": current?.lines.append(.removed(String(line.dropFirst())))\n            case \"\\\\\": continue // \"\\ No newline at end of file\"\n"),
            ("            oldCount: Int(old[1]) ?? 0,", "            oldCount: old.count > 1 ? Int(old[1]) ?? 0 : 1,"),
            ("            newCount: Int(new[1]) ?? 0,", "            newCount: new.count > 1 ? Int(new[1]) ?? 0 : 1,"),
        ],
        findings: [
            ("case \"\\\\\": continue", .head, "No test covers the no-newline marker",
             "The new branch skips `\\ No newline at end of file`, but `DiffParserTests` has no patch containing it. Add a case so this doesn't regress into a context line.",
             .low),
        ]
    )

    static let client = DemoFile(
        path: "web/src/api/client.ts",
        base: #"""
        import { z } from "zod";

        const PullRequest = z.object({
          number: z.number(),
          title: z.string(),
          author: z.string(),
          updatedAt: z.string(),
          additions: z.number(),
          deletions: z.number(),
        });

        export type PullRequest = z.infer<typeof PullRequest>;

        export interface ClientOptions {
          baseUrl: string;
          token: string;
        }

        export class ReviewClient {
          constructor(private readonly options: ClientOptions) {}

          async listPullRequests(repo: string): Promise<PullRequest[]> {
            const res = await fetch(`${this.options.baseUrl}/repos/${repo}/pulls`, {
              headers: { Authorization: `Bearer ${this.options.token}` },
            });
            if (!res.ok) {
              throw new Error(`Request failed: ${res.status}`);
            }
            const body = await res.json();
            return z.array(PullRequest).parse(body);
          }

          async submitReview(repo: string, number: number, event: "APPROVE" | "REQUEST_CHANGES" | "COMMENT", body: string) {
            const res = await fetch(`${this.options.baseUrl}/repos/${repo}/pulls/${number}/reviews`, {
              method: "POST",
              headers: { Authorization: `Bearer ${this.options.token}` },
              body: JSON.stringify({ event, body }),
            });
            return res.ok;
          }
        }
        """#,
        edits: [
            ("  constructor(private readonly options: ClientOptions) {}\n",
             "  private etags = new Map<string, { etag: string; data: PullRequest[] }>();\n\n  constructor(private readonly options: ClientOptions) {}\n"),
            ("""
                const res = await fetch(`${this.options.baseUrl}/repos/${repo}/pulls`, {
                  headers: { Authorization: `Bearer ${this.options.token}` },
                });
            """, """
                const url = `${this.options.baseUrl}/repos/${repo}/pulls`;
                const cached = this.etags.get(url);
                const res = await fetch(url, {
                  headers: {
                    Authorization: `Bearer ${this.options.token}`,
                    ...(cached ? { "If-None-Match": cached.etag } : {}),
                  },
                });
                if (res.status === 304 && cached) {
                  return cached.data;
                }
            """),
            ("    return z.array(PullRequest).parse(body);\n", """
                const data = z.array(PullRequest).parse(body);
                const etag = res.headers.get("ETag");
                if (etag) this.etags.set(url, { etag, data });
                return data;

            """),
            ("    return res.ok;\n", "    if (!res.ok) {\n      throw new Error(`Review submit failed: ${res.status}`);\n    }\n"),
        ],
        findings: [
            ("if (etag) this.etags.set", .head, "ETag cache never evicts",
             "`etags` gains an entry per repository URL for the lifetime of the client. Bound it with an LRU or clear it on sign-out.",
             .medium),
        ]
    )

    static let reviewPanel = DemoFile(
        path: "web/src/components/ReviewPanel.tsx",
        status: .added,
        base: #"""
        import { useState } from "react";
        import type { PullRequest } from "../api/client";

        interface Props {
          pullRequest: PullRequest;
          onSubmit: (event: "APPROVE" | "REQUEST_CHANGES", body: string) => Promise<void>;
        }

        export function ReviewPanel({ pullRequest, onSubmit }: Props) {
          const [body, setBody] = useState("");
          const [busy, setBusy] = useState(false);

          async function submit(event: "APPROVE" | "REQUEST_CHANGES") {
            setBusy(true);
            try {
              await onSubmit(event, body);
              setBody("");
            } finally {
              setBusy(false);
            }
          }

          return (
            <section className="review-panel">
              <h2>
                #{pullRequest.number} {pullRequest.title}
              </h2>
              <p className="meta">
                by {pullRequest.author} · +{pullRequest.additions} −{pullRequest.deletions}
              </p>
              <textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder="Leave a review…" />
              <div className="actions">
                <button disabled={busy} onClick={() => submit("REQUEST_CHANGES")}>
                  Request changes
                </button>
                <button disabled={busy || body.length === 0} onClick={() => submit("APPROVE")}>
                  Approve
                </button>
              </div>
            </section>
          );
        }
        """#,
        findings: [
            ("disabled={busy || body.length === 0}", .head, "Approve is blocked without a message",
             "GitHub accepts approvals with an empty body. Requiring text before **Approve** adds friction to the most common action.",
             .low),
        ]
    )

    static let syncReviews = DemoFile(
        path: "scripts/sync_reviews.py",
        base: #"""
        """Mirror review threads from GitHub into the local cache database."""

        import json
        import sqlite3
        import sys
        import time
        from dataclasses import dataclass

        import requests

        API = "https://api.github.com"


        @dataclass
        class Thread:
            id: str
            path: str
            line: int
            resolved: bool
            body: str


        def fetch_threads(repo: str, number: int, token: str) -> list[Thread]:
            response = requests.get(
                f"{API}/repos/{repo}/pulls/{number}/comments",
                headers={"Authorization": f"Bearer {token}"},
            )
            response.raise_for_status()
            threads = []
            for item in response.json():
                threads.append(
                    Thread(
                        id=str(item["id"]),
                        path=item["path"],
                        line=item.get("line") or 0,
                        resolved=False,
                        body=item["body"],
                    )
                )
            return threads


        def store(db: sqlite3.Connection, threads: list[Thread]) -> None:
            for thread in threads:
                db.execute(
                    "INSERT OR REPLACE INTO threads VALUES (?, ?, ?, ?, ?)",
                    (thread.id, thread.path, thread.line, thread.resolved, thread.body),
                )
            db.commit()


        def main() -> int:
            repo, number, token = sys.argv[1], int(sys.argv[2]), sys.argv[3]
            db = sqlite3.connect("reviews.db")
            started = time.time()
            threads = fetch_threads(repo, number, token)
            store(db, threads)
            print(json.dumps({"synced": len(threads), "seconds": round(time.time() - started, 2)}))
            return 0


        if __name__ == "__main__":
            sys.exit(main())
        """#,
        edits: [
            ("import json\n", "import json\nimport os\n"),
            ("""
            response = requests.get(
                f"{API}/repos/{repo}/pulls/{number}/comments",
                headers={"Authorization": f"Bearer {token}"},
            )
            response.raise_for_status()
            threads = []
            for item in response.json():
        """, """
            threads = []
            url = f"{API}/repos/{repo}/pulls/{number}/comments?per_page=100"
            while url:
                response = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=10)
                response.raise_for_status()
                for item in response.json():
        """),
            ("""
                threads.append(
                    Thread(
                        id=str(item["id"]),
                        path=item["path"],
                        line=item.get("line") or 0,
                        resolved=False,
                        body=item["body"],
                    )
                )
            return threads
        """, """
                    threads.append(
                        Thread(
                            id=str(item["id"]),
                            path=item["path"],
                            line=item.get("line") or 0,
                            resolved=False,
                            body=item["body"],
                        )
                    )
                url = response.links.get("next", {}).get("url")
            return threads
        """),
            ("""
            for thread in threads:
                db.execute(
                    "INSERT OR REPLACE INTO threads VALUES (?, ?, ?, ?, ?)",
                    (thread.id, thread.path, thread.line, thread.resolved, thread.body),
                )
        """, """
            db.executemany(
                "INSERT OR REPLACE INTO threads VALUES (?, ?, ?, ?, ?)",
                [(t.id, t.path, t.line, t.resolved, t.body) for t in threads],
            )
        """),
            ("    repo, number, token = sys.argv[1], int(sys.argv[2]), sys.argv[3]",
             "    repo, number = sys.argv[1], int(sys.argv[2])\n    token = os.environ[\"GITHUB_TOKEN\"]"),
        ],
        findings: [
            ("url = response.links.get", .head, "Pagination ignores secondary rate limits",
             "Large PRs can need dozens of pages. Without honoring `Retry-After` / `x-ratelimit-remaining`, the loop will start failing with 403s on busy repositories.",
             .medium),
        ]
    )

    static let webhook = DemoFile(
        path: "services/webhook/handler.go",
        base: #"""
        package webhook

        import (
        	"crypto/hmac"
        	"crypto/sha256"
        	"encoding/hex"
        	"encoding/json"
        	"io"
        	"log"
        	"net/http"
        )

        type Event struct {
        	Action     string `json:"action"`
        	Number     int    `json:"number"`
        	Repository string `json:"repository"`
        }

        type Handler struct {
        	Secret []byte
        	Queue  chan<- Event
        }

        func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
        	body, err := io.ReadAll(r.Body)
        	if err != nil {
        		http.Error(w, "read error", http.StatusBadRequest)
        		return
        	}
        	if !h.validSignature(r.Header.Get("X-Hub-Signature-256"), body) {
        		http.Error(w, "bad signature", http.StatusUnauthorized)
        		return
        	}
        	var event Event
        	if err := json.Unmarshal(body, &event); err != nil {
        		http.Error(w, "bad payload", http.StatusBadRequest)
        		return
        	}
        	h.Queue <- event
        	log.Printf("queued %s #%d", event.Action, event.Number)
        	w.WriteHeader(http.StatusAccepted)
        }

        func (h *Handler) validSignature(header string, body []byte) bool {
        	mac := hmac.New(sha256.New, h.Secret)
        	mac.Write(body)
        	expected := "sha256=" + hex.EncodeToString(mac.Sum(nil))
        	return header == expected
        }
        """#,
        edits: [
            ("io.ReadAll(r.Body)", "io.ReadAll(io.LimitReader(r.Body, 1<<20))"),
            ("\th.Queue <- event\n", "\tselect {\n\tcase h.Queue <- event:\n\tdefault:\n\t\thttp.Error(w, \"queue full\", http.StatusServiceUnavailable)\n\t\treturn\n\t}\n"),
            ("\treturn header == expected", "\treturn hmac.Equal([]byte(header), []byte(expected))"),
        ],
        findings: [
            ("http.Error(w, \"queue full\"", .head, "Dropped events are not logged",
             "When the queue is full the event is rejected with 503 but nothing is logged or counted, so backpressure is invisible in production.",
             .medium),
        ]
    )

    static let diffCore = DemoFile(
        path: "crates/diff-core/src/lib.rs",
        base: #"""
        //! Line-level diffing used by the Riviu review engine.

        use std::collections::HashMap;

        #[derive(Debug, Clone, PartialEq, Eq)]
        pub enum Op<'a> {
            Equal(&'a str),
            Insert(&'a str),
            Delete(&'a str),
        }

        /// Computes a simple diff by matching unique lines first (patience-style anchor pass).
        pub fn diff<'a>(old: &'a str, new: &'a str) -> Vec<Op<'a>> {
            let a: Vec<&str> = old.lines().collect();
            let b: Vec<&str> = new.lines().collect();
            let mut counts: HashMap<&str, (usize, usize)> = HashMap::new();
            for line in &a {
                counts.entry(line).or_default().0 += 1;
            }
            for line in &b {
                counts.entry(line).or_default().1 += 1;
            }
            let mut ops = Vec::new();
            let (mut i, mut j) = (0, 0);
            while i < a.len() && j < b.len() {
                if a[i] == b[j] {
                    ops.push(Op::Equal(a[i]));
                    i += 1;
                    j += 1;
                } else if counts[a[i]].1 == 0 {
                    ops.push(Op::Delete(a[i]));
                    i += 1;
                } else {
                    ops.push(Op::Insert(b[j]));
                    j += 1;
                }
            }
            ops.extend(a[i..].iter().map(|l| Op::Delete(l)));
            ops.extend(b[j..].iter().map(|l| Op::Insert(l)));
            ops
        }

        #[cfg(test)]
        mod tests {
            use super::*;

            #[test]
            fn detects_insertions() {
                let ops = diff("a\nb", "a\nx\nb");
                assert_eq!(ops, vec![Op::Equal("a"), Op::Insert("x"), Op::Equal("b")]);
            }
        }
        """#,
        edits: [
            ("pub fn diff<'a>", "#[must_use]\npub fn diff<'a>"),
            ("counts[a[i]].1 == 0", "counts.get(a[i]).map_or(true, |c| c.1 == 0)"),
            ("""
                    assert_eq!(ops, vec![Op::Equal("a"), Op::Insert("x"), Op::Equal("b")]);
                }
            """, """
                    assert_eq!(ops, vec![Op::Equal("a"), Op::Insert("x"), Op::Equal("b")]);
                }

                #[test]
                fn handles_empty_input() {
                    assert!(diff("", "").is_empty());
                    assert_eq!(diff("", "a"), vec![Op::Insert("a")]);
                }
            """),
        ]
    )

    static let config = DemoFile(
        path: "config/riviu.json",
        base: #"""
        {
          "review": {
            "dimensions": ["correctness", "security", "performance", "tests"],
            "minConfidence": 70,
            "maxFindingsPerFile": 5
          },
          "providers": {
            "default": "claude-code",
            "explain": "claude-code"
          },
          "github": {
            "pollIntervalSeconds": 60,
            "draftsLocalOnly": true
          }
        }
        """#,
        edits: [
            ("\"tests\"]", "\"tests\", \"api-design\"]"),
            ("\"minConfidence\": 70", "\"minConfidence\": 80"),
            ("\"pollIntervalSeconds\": 60,", "\"pollIntervalSeconds\": 30,\n    \"useETags\": true,"),
        ]
    )

    static let architecture = DemoFile(
        path: "docs/ARCHITECTURE.md",
        base: #"""
        # Riviu architecture

        Riviu is a native macOS code review client.

        ## Modules

        - **DiffEngine** renders unified and split diffs.
        - **Syntax** wraps tree-sitter for highlighting.
        - **ReviewAI** runs review passes against the configured provider.

        ## Data flow

        1. Fetch the pull request and its files.
        2. Build a local worktree for the head commit.
        3. Run AI review passes and anchor findings to lines.

        ## Open questions

        - Should drafts sync to GitHub's pending review?
        """#,
        edits: [
            ("- **ReviewAI** runs review passes against the configured provider.\n",
             "- **ReviewAI** runs review passes against the configured provider.\n- **LSP** hosts one language server per worktree and language.\n"),
            ("3. Run AI review passes and anchor findings to lines.", "3. Run AI review passes in parallel, verify each finding, and anchor it to lines."),
            ("- Should drafts sync to GitHub's pending review?", "- ~~Should drafts sync to GitHub's pending review?~~ Decided: drafts stay local until submit."),
        ]
    )

    static let oldCache = DemoFile(
        path: "Sources/Legacy/OldCache.swift",
        status: .deleted,
        base: #"""
        import Foundation

        final class OldCache {
            static let shared = OldCache()
            private var storage: [String: Data] = [:]
            private let lock = NSLock()

            func value(for key: String) -> Data? {
                lock.lock(); defer { lock.unlock() }
                return storage[key]
            }

            func set(_ data: Data, for key: String) {
                lock.lock(); defer { lock.unlock() }
                storage[key] = data
            }
        }
        """#,
        findings: [
            ("static let shared = OldCache()", .base, "Remaining callers of OldCache.shared",
             "`OldCache.shared` is still referenced from `ReviewListViewModel` and `ThumbnailLoader` on the head commit. Deleting the file will break the build.",
             .high),
        ]
    )
}
