import Foundation

/// 与官方考生平台首页「考生服务大厅」一致的 7 项入口。
enum StudentHomeService: String, CaseIterable, Identifiable, Hashable {
  case examRegistration
  case onlinePayment
  case ticketPrint
  case queryCenter
  case applicationProcessing
  case formPrint
  case faq

  var id: String { rawValue }

  var title: String {
    switch self {
    case .examRegistration: "考试报名"
    case .onlinePayment: "网上缴费"
    case .ticketPrint: "准考证打印"
    case .queryCenter: "查询中心"
    case .applicationProcessing: "申请办理"
    case .formPrint: "表证打印"
    case .faq: "常见 Q/A"
    }
  }

  var subtitle: String {
    switch self {
    case .examRegistration: "报名、资格审核与状态查询"
    case .onlinePayment: "考试相关费用在线缴纳"
    case .ticketPrint: "准考证下载与打印"
    case .queryCenter: "成绩、录取、投档等查询"
    case .applicationProcessing: "成绩复核、信息变更等申请"
    case .formPrint: "报名表、确认单等表证打印"
    case .faq: "报名指南与常见问题"
    }
  }

  var systemImage: String {
    switch self {
    case .examRegistration: "square.and.pencil"
    case .onlinePayment: "creditcard"
    case .ticketPrint: "printer"
    case .queryCenter: "chart.bar.doc.horizontal"
    case .applicationProcessing: "doc.text"
    case .formPrint: "list.bullet.rectangle"
    case .faq: "questionmark.bubble"
    }
  }

  /// 官方 `systemTotal` 的 `src` 路由片段（与前端 hash 路由一致）。
  var routeSource: String {
    switch self {
    case .examRegistration: "/home/ExamEnroll"
    case .onlinePayment: "/home/PayFee"
    case .ticketPrint: "/home/TicketPrint"
    case .queryCenter: "/home/ScoreQuery"
    case .applicationProcessing: "/home/Apply"
    case .formPrint: "/home/AdTicket"
    case .faq: "/home/Notice"
    }
  }

  /// 用于匹配 `stusercenter/serlist` 返回项。
  var matchKeywords: [String] {
    switch self {
    case .examRegistration: ["考试报名", "报名"]
    case .onlinePayment: ["网上缴费", "缴费", "支付"]
    case .ticketPrint: ["准考证", "打印准考证"]
    case .queryCenter: ["查询中心", "成绩查询", "录取查询", "投档"]
    case .applicationProcessing: ["申请办理", "申请"]
    case .formPrint: ["表证打印", "表证", "确认单"]
    case .faq: ["常见", "问答", "指南", "Q/A"]
    }
  }

  func fallbackURL(planCode: String = OfficialServiceResolver.defaultPlanCode, token: String? = nil) -> URL {
    OfficialServiceResolver.systemTotalURL(source: routeSource, planCode: planCode, token: token)
  }
}
