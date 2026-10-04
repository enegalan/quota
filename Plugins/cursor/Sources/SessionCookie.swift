import Foundation

enum SessionCookie {
    static func value(userID: String, accessToken: String) -> String {
        userID + CursorConstants.cookieSubjectSeparator + accessToken
    }

    static func header(userID: String, accessToken: String) -> String {
        CursorConstants.sessionCookieName + "=" + value(userID: userID, accessToken: accessToken)
    }
}
