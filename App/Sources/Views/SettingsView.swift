import SwiftUI
import ServiceManagement
import KodizSystem

public struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = true
    @AppStorage("defaultConnections") private var defaultConnections: Int = 8
    @AppStorage("maxConcurrentDownloads") private var maxConcurrent: Int = 4
    @AppStorage("speedLimitKB") private var speedLimitKB: Int = 0
    @AppStorage("preventSleep") private var preventSleep: Bool = true

    public init() {}

    public var body: some View {
        TabView {
            // General Tab
            Form {
                Section("Başlangıç & Sistem") {
                    Toggle("Oturum açılışında başlat", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            if newValue {
                                try? LoginItemManager.register()
                            } else {
                                try? LoginItemManager.unregister()
                            }
                        }

                    Toggle("Aktif indirme varken Mac'in uyumasını engelle", isOn: $preventSleep)
                }

                Section("Arayüz") {
                    Text("Menü çubuğunda canlı hız ve aktif indirme sayısı gösterilir.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("Genel", systemImage: "gear")
            }

            // Downloads Tab
            Form {
                Section("Bağlantı & Performans") {
                    Picker("Varsayılan Bağlantı Sayısı", selection: $defaultConnections) {
                        ForEach([1, 2, 4, 8, 12, 16], id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }

                    Stepper("Eşzamanlı İndirme Sınırı: \(maxConcurrent)", value: $maxConcurrent, in: 1...10)

                    HStack {
                        Text("Genel Hız Sınırı:")
                        TextField("0 = Sınırsız", value: $speedLimitKB, format: .number)
                            .frame(width: 100)
                        Text("KB/s")
                    }
                }
            }
            .tabItem {
                Label("İndirmeler", systemImage: "arrow.down.circle")
            }

            // Browsers Tab
            Form {
                Section("Tarayıcı Entegrasyonları") {
                    HStack {
                        Image(systemName: "globe")
                        Text("Safari")
                        Spacer()
                        Text("Uzantı Etkin").foregroundColor(.green).font(.caption)
                    }
                    HStack {
                        Image(systemName: "globe")
                        Text("Google Chrome")
                        Spacer()
                        Text("NMH Bağlı").foregroundColor(.green).font(.caption)
                    }
                    HStack {
                        Image(systemName: "globe")
                        Text("Mozilla Firefox")
                        Spacer()
                        Text("NMH Bağlı").foregroundColor(.green).font(.caption)
                    }
                }
            }
            .tabItem {
                Label("Tarayıcılar", systemImage: "network")
            }

            // Video Tab
            Form {
                Section("Video Motoru (yt-dlp)") {
                    HStack {
                        Text("yt-dlp Sürümü:")
                        Spacer()
                        Text("2026.03.01 (Gömülü)").foregroundColor(.secondary)
                        Button("Güncelle") {}
                    }
                    HStack {
                        Text("JavaScript Runtime:")
                        Spacer()
                        Text("QuickJS-ng 0.12").foregroundColor(.secondary)
                    }
                    Picker("Varsayılan Format", selection: .constant("1080p")) {
                        Text("En İyi (≤1080p MP4)").tag("1080p")
                        Text("En Yüksek Kalite").tag("max")
                        Text("Yalnızca Ses (MP3/M4A)").tag("audio")
                    }
                }
            }
            .tabItem {
                Label("Video", systemImage: "play.rectangle")
            }
        }
        .padding(20)
        .frame(width: 500, height: 350)
    }
}
