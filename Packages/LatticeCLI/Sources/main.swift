import Foundation
import Config
import AppCore

@main
enum LatticeCLIMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let verb = args.first else {
            printUsage()
            exit(1)
        }

        switch verb {
        case "doctor":
            var configPath: String?
            var i = 1
            while i < args.count {
                if args[i] == "--config", i + 1 < args.count {
                    configPath = args[i + 1]
                    i += 2
                    continue
                }
                i += 1
            }
            let url = configPath.map { URL(fileURLWithPath: $0) } ?? ConfigLoader.defaultFileURL()
            let report = Doctor.check(configURL: url)
            print(report.text)
            exit(report.ok ? 0 : 1)

        case "run":
            let cmd = args.dropFirst().joined(separator: " ")
            guard !cmd.isEmpty else {
                fputs("usage: lattice run <command>\n", stderr)
                exit(1)
            }
            do {
                let response = try CommandSocketClient.send(
                    .init(command: "run", args: Array(args.dropFirst()))
                )
                if response.ok {
                    if !response.output.isEmpty { print(response.output) }
                    exit(0)
                } else {
                    fputs((response.error ?? "failed") + "\n", stderr)
                    exit(1)
                }
            } catch {
                fputs("lattice: cannot reach Lattice app (\(error)). Is it running?\n", stderr)
                exit(1)
            }

        case let v where v.hasPrefix("list-"):
            do {
                let response = try CommandSocketClient.send(.init(command: v))
                if response.ok {
                    print(response.output)
                    exit(0)
                } else {
                    fputs((response.error ?? "failed") + "\n", stderr)
                    exit(1)
                }
            } catch {
                fputs("lattice: cannot reach Lattice app (\(error)). Is it running?\n", stderr)
                exit(1)
            }

        case "help", "-h", "--help":
            printUsage()
            exit(0)

        default:
            // Forward as a Lattice command.
            do {
                let response = try CommandSocketClient.send(
                    .init(command: verb, args: Array(args.dropFirst()))
                )
                if response.ok {
                    if !response.output.isEmpty { print(response.output) }
                    exit(0)
                } else {
                    fputs((response.error ?? "failed") + "\n", stderr)
                    exit(1)
                }
            } catch {
                fputs("lattice: cannot reach Lattice app (\(error)). Is it running?\n", stderr)
                exit(1)
            }
        }
    }

    static func printUsage() {
        print(
            """
            lattice — Lattice window manager CLI
            Usage:
              lattice doctor [--config <path>]
              lattice run <command>
              lattice list-windows | list-workspaces | list-displays | list-modes
              lattice <command> …
            Talks to the running Lattice app over a per-user Unix socket (Caches/TMPDIR).
            """
        )
    }
}
