import SwiftUI
import WidgetKit
import XCTest
import MoneyMapShared

/// Renders the production widget views with a transparent gutter. Any painted
/// pixel outside a seven-point safe inset indicates crowding or overflow.
@MainActor
final class WidgetLayoutTests: XCTestCase {
    func testWidgetSizeAndContentMatrix() throws {
        let now = Date(timeIntervalSince1970: 1_789_732_800)
        let bills = (0..<5).map { index in
            WidgetBillSummary(id: UUID(), name: "Very Long Household Electricity and Internet Bill \(index)",
                              dueDate: now.addingTimeInterval(Double(index - 2) * 86400),
                              amount: 987654.32, category: .utilities, autopayEnabled: true, gracePeriodDays: 10)
        }
        let ordinaryBill = WidgetBillSummary(id: UUID(), name: "Rent", dueDate: now.addingTimeInterval(2 * 86400), amount: 1450, category: .rent)
        let sizes: [(WidgetFamily, CGSize)] = [
            (.systemSmall, CGSize(width: 155, height: 155)),
            (.systemSmall, CGSize(width: 170, height: 170)),
            (.systemMedium, CGSize(width: 329, height: 155)),
            (.systemMedium, CGSize(width: 364, height: 170))
        ]
        for (family, size) in sizes {
            for typeSize in [DynamicTypeSize.large, .xxxLarge] {
                var cases: [(String, AnyView)] = [
                    ("Actions", AnyView(MainWidgetEntryView(entry: .init(date: now), familyOverride: family))),
                    ("Bill normal", AnyView(NextBillWidgetView(entry: .init(date: now, bill: ordinaryBill), familyOverride: family))),
                    ("Bill long", AnyView(NextBillWidgetView(entry: .init(date: now, bill: bills[0]), familyOverride: family))),
                    ("Bill empty", AnyView(NextBillWidgetView(entry: .init(date: now, bill: nil), familyOverride: family)))
                ]
                if family == .systemSmall {
                    cases += [
                        ("Payday", AnyView(PaydayCountdownWidgetView(entry: .init(date: now, nextPayday: now.addingTimeInterval(86400 * 7), cycleStart: now.addingTimeInterval(-86400 * 7))))),
                        ("Payday overdue", AnyView(PaydayCountdownWidgetView(entry: .init(date: now, nextPayday: now.addingTimeInterval(-86400))))),
                        ("Payday empty", AnyView(PaydayCountdownWidgetView(entry: .init(date: now, nextPayday: nil))))
                    ]
                } else {
                    cases += [
                        ("Bills full", AnyView(UpcomingBillsListWidgetView(entry: .init(date: now, bills: bills)))),
                        ("Bills empty", AnyView(UpcomingBillsListWidgetView(entry: .init(date: now, bills: [])))),
                        ("Bills single", AnyView(UpcomingBillsListWidgetView(entry: .init(date: now, bills: Array(bills.prefix(1))))))
                    ]
                }
                for (name, view) in cases {
                    let label = "\(name)-\(Int(size.width))x\(Int(size.height))-\(typeSize)"
                    let content = view.environment(\.dynamicTypeSize, typeSize)
                        .environment(\.colorScheme, .dark)
                        .frame(width: size.width, height: size.height)
                    let renderer = ImageRenderer(content: content.padding(20))
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.cgImage, label)
                    let width = image.width, height = image.height
                    var pixels = [UInt8](repeating: 0, count: width * height * 4)
                    let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    XCTAssertGreaterThan(stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 16 }.count, 50, "\(label): render must contain visible content")
                    var escaped = 0
                    for y in 0..<height {
                        for x in 0..<width where x < 27 || x >= width - 27 || y < 27 || y >= height - 27 {
                            if pixels[(y * width + x) * 4 + 3] > 16 { escaped += 1 }
                        }
                    }
                    XCTAssertEqual(escaped, 0, "\(label): painted pixels outside the widget safe inset")
                    let preview = ImageRenderer(content: content.background(Color(red: 0.09, green: 0.25, blue: 0.3)))
                    preview.scale = 2
                    let attachment = XCTAttachment(image: try XCTUnwrap(preview.uiImage))
                    attachment.name = label
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
