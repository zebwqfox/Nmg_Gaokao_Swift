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
    XCTAssertTrue(categories.contains { $0.url.host == "www.nm.zsks.cn" })
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
