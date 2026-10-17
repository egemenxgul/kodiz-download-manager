import Foundation

public struct MediaFormatOption: Sendable, Identifiable {
    public var id: String { formatId }
    public let formatId: String
    public let resolution: String?
    public let ext: String
    public let vcodec: String?
    public let acodec: String?
    public let filesizeEstimate: Int64?
    public let fps: Double?
    public let isAudioOnly: Bool
    public let isVideoOnly: Bool

    public init(
        formatId: String,
        resolution: String? = nil,
        ext: String,
        vcodec: String? = nil,
        acodec: String? = nil,
        filesizeEstimate: Int64? = nil,
        fps: Double? = nil,
        isAudioOnly: Bool = false,
        isVideoOnly: Bool = false
    ) {
        self.formatId = formatId
        self.resolution = resolution
        self.ext = ext
        self.vcodec = vcodec
        self.acodec = acodec
        self.filesizeEstimate = filesizeEstimate
        self.fps = fps
        self.isAudioOnly = isAudioOnly
        self.isVideoOnly = isVideoOnly
    }
}

public struct MediaMetadata: Sendable {
    public let id: String
    public let title: String
    public let duration: Double?
    public let uploader: String?
    public let thumbnail: String?
    public let formats: [MediaFormatOption]
    public let isPlaylist: Bool
    public let playlistCount: Int?

    public init(
        id: String,
        title: String,
        duration: Double? = nil,
        uploader: String? = nil,
        thumbnail: String? = nil,
        formats: [MediaFormatOption] = [],
        isPlaylist: Bool = false,
        playlistCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.uploader = uploader
        self.thumbnail = thumbnail
        self.formats = formats
        self.isPlaylist = isPlaylist
        self.playlistCount = playlistCount
    }
}
