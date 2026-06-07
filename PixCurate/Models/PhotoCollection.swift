import Foundation

struct PhotoCollection: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var fileCount: Int = 0
    /// 親グループの id。nil ならトップレベル。
    /// グループ（フォルダ的なまとめ）も通常のコレクションも同じ型で表し、
    /// 子を持つノードをグループとして扱う。
    var parentId: UUID? = nil
}
