@main struct VehicleNamesTests {
    static func main() {
        let names = [VehicleNames.key(for: "SmartStartBT-419F"): "My Truck", VehicleNames.key(for: "SmartStartBT-321F"): "Family Car"]
        precondition(VehicleNames.displayName(for: "SmartStartBT-419F", names: names) == "My Truck")
        precondition(VehicleNames.displayName(for: "smartstartbt-321f", names: names) == "Family Car")
        precondition(VehicleNames.displayName(for: "SmartStartBT-0000", names: names) == "SmartStartBT-0000")
        precondition(VehicleNames.limited("12345678901234567890123") == "12345678901234567890")
        precondition(VehicleNames.limited("Car\nName") == "CarName")
        print("Vehicle name checks passed")
    }
}
