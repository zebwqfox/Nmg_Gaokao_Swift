import WebKit
import XCTest
@testable import NeimengGaokao

final class NeimengGaokaoTests: XCTestCase {
  func testCaptchaUsesConfiguredLength() {
    let captcha = OfficialStudentClient().makeCaptcha(length: 6)
    XCTAssertEqual(captcha.count, 6)
  }

  func testOfficialContentCategoriesOnlyIncludeFeedSources() {
    let categories = OfficialContentClient().categories
    XCTAssertEqual(categories.map(\.id), ["notice", "latest-news"])
    XCTAssertTrue(categories.allSatisfy { $0.url.host == "www.nm.zsks.cn" })
  }

  func testOfficialFeedPaginationBuildsIndexURLs() {
    let category = OfficialCategory(
      id: "notice",
      title: "通知公告",
      kind: .notice,
      examType: nil,
      url: URL(string: "https://www.nm.zsks.cn/tzgg/")!
    )
    XCTAssertEqual(
      OfficialFeedPagination.pageURL(for: category, page: 1).absoluteString,
      "https://www.nm.zsks.cn/tzgg/"
    )
    XCTAssertEqual(
      OfficialFeedPagination.pageURL(for: category, page: 2).absoluteString,
      "https://www.nm.zsks.cn/tzgg/index_2.html"
    )
  }

  func testOfficialSiteSearchBuildsContentQueryURL() {
    let url = OfficialSiteSearch.pageURL(query: "高考", page: 1)
    XCTAssertEqual(url.absoluteString, "https://www.nm.zsks.cn/web/search/375?content=%E9%AB%98%E8%80%83")

    let page2 = OfficialSiteSearch.pageURL(query: "高考", page: 2)
    XCTAssertTrue(page2.absoluteString.contains("content="))
    XCTAssertTrue(page2.absoluteString.contains("page=2"))
  }

  func testOfficialSiteSearchParsesTotalPages() {
    XCTAssertEqual(OfficialSiteSearch.totalPages(in: "共 33页"), 33)
    XCTAssertEqual(OfficialSiteSearch.totalPages(in: "共1,005条 共101页"), 101)
  }

  func testOfficialSiteSearchCleansBracketPrefix() {
    XCTAssertEqual(
      OfficialSiteSearch.cleanedTitle("【高考公告】 内蒙古自治区2026年普通高考报名问题解答"),
      "内蒙古自治区2026年普通高考报名问题解答"
    )
  }

  func testOfficialFeedPaginationReadsTotalPages() {
    let html = """
    <a href="index_2.html">2</a>
    <a href="index_3.html">3</a>
    <a href="index_12.html">尾页</a>
    """
    XCTAssertEqual(OfficialFeedPagination.totalPages(in: html), 12)
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

  func testOfficialArticleListFilterRejectsExamCategoryLinks() {
    XCTAssertFalse(
      OfficialArticleListFilter.shouldKeepListLink(
        title: "普通高考",
        url: URL(string: "https://www.nm.zsks.cn/kszs/ptgk/")!,
        hasNearbyDate: false
      )
    )
    XCTAssertTrue(
      OfficialArticleListFilter.shouldKeepListLink(
        title: "2025年成人高考录取结束，请考生查询录取结果",
        url: URL(string: "https://www.nm.zsks.cn/kszs/crgk/202512/t20251218_12345.html")!,
        hasNearbyDate: true
      )
    )
  }

  func testOfficialArticleParserRemovesScriptsAndFindsImages() {
    let html = """
    <h1>关于公布2026年体育统考成绩的公告</h1>
    发布时间：2026-05-07 18:13 来源：普通高校招生考试处
    <div class="TRS_Editor">
      <p>按照工作安排，我区2026年体育统考成绩定于5月7日向社会公布。</p>
      <p><img src="/upload/2026/test.jpg" alt="示意图"></p>
    </div>
    var xgwd = '';
    document.write('相关文档');
    function goPAGE() {}
  """
    let fallback = CachedArticle(
      id: "test",
      categoryID: "notice",
      categoryTitle: "通知公告",
      kind: .notice,
      title: "fallback",
      originalURL: URL(string: "https://www.nm.zsks.cn/tzgg/202605/t20260507_46369.html")!
    )
    let parsed = OfficialArticleParser.parse(html: html, fallback: fallback)
    XCTAssertEqual(parsed.title, "关于公布2026年体育统考成绩的公告")
    XCTAssertFalse(parsed.body.contains("document.write"))
    XCTAssertFalse(parsed.body.contains("function goPAGE"))
    XCTAssertTrue(parsed.body.contains("体育统考成绩"))
    XCTAssertTrue(parsed.contentBlocks.contains {
      if case .image = $0 { return true }
      return false
    })
    XCTAssertFalse(parsed.attachments.contains { $0.fileType == "image" })
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
