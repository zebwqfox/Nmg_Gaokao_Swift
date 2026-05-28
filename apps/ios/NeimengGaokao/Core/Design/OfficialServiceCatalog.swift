import Foundation

struct OfficialService: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let systemImage: String
  let url: URL
  let requiresLogin: Bool
  let group: String
}

enum OfficialServiceCatalog {
  static let studentPortal = URL(string: "https://www4.nm.zsks.cn/BaseStudent/")!
  static let mainSite = URL(string: "https://www.nm.zsks.cn/")!

  static let services: [OfficialService] = [
    OfficialService(
      id: "student-portal",
      title: "考生办事平台",
      subtitle: "报名、查询、打印、缴费等官方入口",
      systemImage: "person.text.rectangle",
      url: studentPortal,
      requiresLogin: true,
      group: "常用"
    ),
    OfficialService(
      id: "ticket-print",
      title: "准考证打印",
      subtitle: "进入官方打印流程，保留原站登录态",
      systemImage: "printer",
      url: URL(string: "https://www4.nm.zsks.cn/BaseStudent/systemTotal?src=/home/TicketPrint&planCode=202610010001")!,
      requiresLogin: true,
      group: "高考"
    ),
    OfficialService(
      id: "registration",
      title: "考试报名",
      subtitle: "报名、资格审核、报名状态查询",
      systemImage: "square.and.pencil",
      url: studentPortal,
      requiresLogin: true,
      group: "高考"
    ),
    OfficialService(
      id: "score",
      title: "成绩查询",
      subtitle: "成绩发布后进入官方查询入口",
      systemImage: "chart.bar.doc.horizontal",
      url: studentPortal,
      requiresLogin: true,
      group: "查询"
    ),
    OfficialService(
      id: "volunteer",
      title: "志愿填报",
      subtitle: "官方填报页面，使用受控 WebView 打开",
      systemImage: "list.bullet.clipboard",
      url: studentPortal,
      requiresLogin: true,
      group: "录取"
    ),
    OfficialService(
      id: "admission",
      title: "录取查询",
      subtitle: "录取结果、投档状态等查询入口",
      systemImage: "checkmark.seal",
      url: studentPortal,
      requiresLogin: true,
      group: "录取"
    ),
    OfficialService(
      id: "payment",
      title: "网上缴费",
      subtitle: "支付类流程只在官方网页内完成",
      systemImage: "creditcard",
      url: studentPortal,
      requiresLogin: true,
      group: "常用"
    ),
    OfficialService(
      id: "photo",
      title: "照片采集",
      subtitle: "进入官方照片采集与确认流程",
      systemImage: "camera",
      url: studentPortal,
      requiresLogin: true,
      group: "常用"
    ),
    OfficialService(
      id: "official-services",
      title: "主站服务平台",
      subtitle: "报名、成绩、志愿、录取入口聚合页",
      systemImage: "safari",
      url: URL(string: "https://www.nm.zsks.cn/fwpt/")!,
      requiresLogin: false,
      group: "官方"
    )
  ]
}
