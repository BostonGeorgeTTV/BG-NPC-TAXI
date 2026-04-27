Config = {}

Config.Command = 'taxi'
Config.TaxiModel = `taxi`
Config.DriverModel = `s_m_m_gentransport`

Config.SpawnDistanceMin = 120.0
Config.SpawnDistanceMax = 220.0
Config.ArriveStopDistance = 16.0
Config.PlayerBoardDistance = 10.0
Config.DestinationStopDistance = 18.0
Config.DeleteDistanceFromPlayer = 180.0

Config.MaxSpeedKmh = 80.0
Config.MaxSpeedMs = Config.MaxSpeedKmh / 3.6
Config.DrivingStyle = 786603
Config.WaitingDrivingStyle = 786603
Config.CruiseDrivingStyle = 786603

Config.BaseFare = 10
Config.PricePerKm = 5
Config.MinimumBankToOrder = 250
Config.CancelKey = 73 -- X

Config.DrawTextHeight = 1.2
Config.DrawTextScale = 0.35

Config.Blip = {
    sprite = 198,
    color = 5,
    scale = 0.85,
    name = 'Taxi NPC'
}

Config.Debug = false

Config.DriveStopRadius = 15.0
Config.RepathIfStoppedSeconds = 6
Config.ForceRoadNodes = true
