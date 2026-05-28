import WebKit
import XCTest
@testable import NeimengGaokao

final class NeimengGaokaoTests: XCTestCase {
  func testCaptchaUsesConfiguredLength() {
    let captcha = OfficialStudentClient().makeCaptcha(length: 6)
    XCTAssertEqual(captcha.count, 6)
  }

  func testOfficialContentCategoriesIncludeGaokaoPolicy() {
    let categories = OfficialContentClient().categories
    XCTAssertTrue(categories.contains { $0.id == "gaokao-policy" })
    XCTAssertTrue(categories.contains { $0.id == "notice" })
    XCTAssertTrue(categories.contains { $0.id == "latest-news" })
    XCTAssertTrue(categories.contains { $0.url.host == "www.nm.zsks.cn" })
  }

  func testImportantNewsRankerPinsGaokaoNotice() {
    let article = CachedArticle(
      id: "a",
      categoryID: "notice",
      categoryTitle: "通知公告",
      kind: .notice,
      title: "禁止携带手机、手表（手环）、智能眼镜等物品参加高考的温馨提醒",
      summary: "",
      body: "",
      source: nil,
      publishedAt: Date(),
      originalURL: URL(string: "https://www.nm.zsks.cn/tzgg/example.html")!
    )
    XCTAssertTrue(ImportantNewsRanker.isPinned(article))
    XCTAssertEqual(ImportantNewsRanker.pinned([article]).count, 1)
  }

  func testOfficialServiceResolverMatchesByKeyword() {
    let resolver = OfficialServiceResolver()
    let services = [
      OfficialStudentService(
        name: "2026年普通高校招生准考证打印",
        type: "高考",
        url: nil,
        planCode: "202610010001",
        src: "/home/TicketPrint",
        outFlag: nil,
        examTypeCode: nil,
        scheCode: nil
      )
    ]
    let matched = resolver.matchOfficialService(for: .ticketPrint, in: services)
    XCTAssertEqual(matched?.name, "2026年普通高校招生准考证打印")
  }

  func testOfficialWebSessionScriptInjectsExpectedStorageKeys() {
    let script = OfficialWebSessionScript.makeUserScript(
      token: "sample-token",
      baseUserInfoJSON: #"{"token":"sample-token","name":"test"}"#
    )
    XCTAssertNotNil(script)
    XCTAssertTrue(script?.source.contains("STUTOKEN") == true)
    XCTAssertTrue(script?.source.contains("BASEUSERINFO") == true)
  }

  func testOfficialStudentServiceBuildsSystemTotalURL() {
    let service = OfficialStudentService(
      name: "准考证打印",
      type: "高考",
      url: "https://www4.nm.zsks.cn/exam/student/zhfw/web/index.html#/home/TicketPrint",
      planCode: "202610010001",
      src: nil,
      outFlag: nil,
      examTypeCode: nil,
      scheCode: nil
    )
    let url = service.launchURL(token: "token")
    XCTAssertEqual(url.host, "www4.nm.zsks.cn")
    XCTAssertTrue(url.absoluteString.contains("systemTotal"))
    XCTAssertTrue(url.absoluteString.contains("planCode=202610010001"))
  }
}
