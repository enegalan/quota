import Testing
@testable import App

@Suite("Popover order")
struct PopoverOrderTests {
    @Test("Saved order keeps available items and appends new ones")
    func savedOrder() {
        #expect(PopoverOrder.arranged(["5h", "week", "quota"], accordingTo: ["quota", "gone", "quota", "5h"]) == [
            "quota",
            "5h",
            "week",
        ])
    }

    @Test("Moving items works in either direction and ignores missing items")
    func move() {
        let ids = ["5h", "week", "quota"]
        #expect(PopoverOrder.moving("5h", to: "quota", in: ids) == ["week", "quota", "5h"])
        #expect(PopoverOrder.moving("quota", to: "5h", in: ids) == ["quota", "5h", "week"])
        #expect(PopoverOrder.moving("missing", to: "5h", in: ids) == ids)
    }

    @Test("Provider accounts have independent saved orders")
    func accountKeys() {
        #expect(PopoverOrder.key(providerID: "claude", account: "one") != PopoverOrder.key(
            providerID: "claude",
            account: "two"
        ))
    }
}
