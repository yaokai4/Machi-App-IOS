import Foundation

enum ScreenState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error(String)
}
