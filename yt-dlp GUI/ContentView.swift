import SwiftUI
import AppKit

struct ContentView: View {
    enum YtDlpLocation: String, CaseIterable, Identifiable {
        case homebrew = "/usr/local/bin/yt-dlp"
        case macports = "/opt/local/bin/yt-dlp"
        case manual = ""

        var id: String { self.rawValue }

        var label: String {
            switch self {
            case .homebrew: return NSLocalizedString("homebrew_path", comment: "")
            case .macports: return NSLocalizedString("macports_path", comment: "")
            case .manual: return NSLocalizedString("manual", comment: "")
            }
        }
    }

    @State private var url: String = ""
    @State private var path: String = ""
    @State private var ytDlpPath: String = ""
    @State private var audio_only: Bool = false
    @State private var showYtDlpAlert = false
    @State private var showFfmpegAlert = false
    @State private var selectedOption: YtDlpLocation = .manual
    @State private var selectedQuality: String = "1080p"

    @State private var downloadProgress: Double = 0.0
    @State private var isDownloading = false
    @State private var downloadCompleted = false
    @State private var showLog = false
    @State private var logText = ""
    @State private var currentProcess: Process? = nil

    var availableQualities = ["144p", "240p", "360p", "480p", "720p", "1080p"]

    var ffmpeg_found: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffmpeg"]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    func startDownload() {
        guard !ytDlpPath.isEmpty else {
            showYtDlpAlert = true
            return
        }

        let testProcess = Process()
        testProcess.executableURL = URL(fileURLWithPath: ytDlpPath)
        testProcess.arguments = ["--version"]

        do {
            try testProcess.run()
            testProcess.waitUntilExit()
            if testProcess.terminationStatus != 0 {
                showYtDlpAlert = true
                return
            }
        } catch {
            showYtDlpAlert = true
            return
        }

        if !ffmpeg_found {
            showFfmpegAlert = true
        }

        isDownloading = true
        downloadCompleted = false
        downloadProgress = 0
        logText = ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)

        var args = [url, "-o", "\(path)/%(title)s.%(ext)s"]
        if audio_only {
            args.append(contentsOf: ["-f", "bestaudio", "--extract-audio", "--audio-format", "mp3"])
        } else {
            args.append(contentsOf: ["-f", "bestvideo[height<=\(selectedQuality.replacingOccurrences(of: "p", with: ""))]+bestaudio/best"])
        }
        args.append("--newline")

        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                DispatchQueue.main.async {
                    isDownloading = false
                    downloadCompleted = true
                }
                return
            }
            if let line = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    logText += line
                    parseProgress(line: line)
                }
            }
        }

        currentProcess = process

        do {
            try process.run()
        } catch {
            print("Errore: \(error)")
            DispatchQueue.main.async {
                isDownloading = false
            }
        }
    }

    func cancelDownload() {
        currentProcess?.terminate()
        currentProcess = nil
        isDownloading = false
        logText += "\n" + NSLocalizedString("download_canceled", comment: "")
    }

    func parseProgress(line: String) {
        if line.contains("[download]") {
            if let percentRange = line.range(of: #"(\d{1,3}\.\d)%"#, options: .regularExpression) {
                let percentString = String(line[percentRange]).replacingOccurrences(of: "%", with: "")
                if let percent = Double(percentString) {
                    downloadProgress = percent / 100.0
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("app_title", comment: "")) // Titolo app

            TextField(NSLocalizedString("url_placeholder", comment: ""), text: $url)

            HStack {
                TextField(NSLocalizedString("path_placeholder", comment: ""), text: $path)
                Button(NSLocalizedString("browse", comment: "")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK {
                        if let selectedURL = panel.url {
                            path = selectedURL.path
                        }
                    }
                }
            }

            VStack(alignment: .leading) {
                HStack {
                    TextField(NSLocalizedString("yt_dlp_path", comment: ""), text: $ytDlpPath)
                    Button(NSLocalizedString("browse", comment: "")) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK {
                            if let selectedURL = panel.url {
                                ytDlpPath = selectedURL.path
                                selectedOption = .manual
                            }
                        }
                    }
                }

                Picker(NSLocalizedString("default_path_label", comment: ""), selection: $selectedOption) {
                    ForEach(YtDlpLocation.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .onChange(of: selectedOption) { newValue in
                    ytDlpPath = newValue.rawValue
                }
            }

            HStack {
                Button(isDownloading ? NSLocalizedString("downloading_button", comment: "") : NSLocalizedString("download_button", comment: "")) {
                    if !isDownloading {
                        startDownload()
                    }
                }
                .disabled(isDownloading)
                .padding()
                .background(isDownloading ? Color.gray : Color.accentColor)
                .cornerRadius(10)
                .foregroundColor(.white)

                if isDownloading {
                    Button(NSLocalizedString("cancel_button", comment: "")) {
                        cancelDownload()
                    }
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
                    .foregroundColor(.white)
                }

                Toggle(isOn: $audio_only) {
                    Text(NSLocalizedString("audio_only", comment: ""))
                }
                .toggleStyle(.switch)

                Picker(NSLocalizedString("quality_label", comment: ""), selection: $selectedQuality) {
                    ForEach(availableQualities, id: \.self) { quality in
                        Text(quality).tag(quality)
                    }
                }
                .frame(width: 120)
                .labelsHidden()
            }

            ProgressView(value: downloadProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(maxWidth: .infinity)

            if downloadCompleted {
                Text(NSLocalizedString("download_complete", comment: ""))
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
