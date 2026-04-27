local ESX = exports['es_extended']:getSharedObject()

local Taxi = {
    active = false,
    vehicle = nil,
    driver = nil,
    blip = nil,
    fareActive = false,
    fareAmount = 0,
    traveledMeters = 0.0,
    waitingWaypoint = false,
    destination = nil,
    rawDestination = nil,
    cancelling = false,
    hasCharged = false,
    notifiedBoard = false,
    notifiedWaypoint = false,
    lastWaypointNotify = 0
}

local function debugPrint(...)
    if Config.Debug then
        print('[npc_taxi]', ...)
    end
end

local function notify(msg, msgType)
    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(msg, msgType or 'info')
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function loadModel(model)
    if not IsModelInCdimage(model) then return false end
    RequestModel(model)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(model) do
        Wait(50)
        if GetGameTimer() > timeout then return false end
    end
    return true
end

local function deleteEntitySafe(entity)
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

local function removeTaxiBlip()
    if Taxi.blip and DoesBlipExist(Taxi.blip) then
        RemoveBlip(Taxi.blip)
        Taxi.blip = nil
    end
end

local function getPlayerSeat(vehicle)
    local playerPed = PlayerPedId()
    if not vehicle or not DoesEntityExist(vehicle) then return nil end

    for i = -1, GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2 do
        if GetPedInVehicleSeat(vehicle, i) == playerPed then
            return i
        end
    end

    return nil
end

local setTaxiNuiVisible
local updateTaxiNui

local function resetTaxiState()
    removeTaxiBlip()
    setTaxiNuiVisible(false)
    Taxi.active = false
    Taxi.fareActive = false
    Taxi.fareAmount = 0
    Taxi.traveledMeters = 0.0
    Taxi.waitingWaypoint = false
    Taxi.destination = nil
    Taxi.rawDestination = nil
    Taxi.cancelling = false
    Taxi.hasCharged = false
    Taxi.notifiedBoard = false
    Taxi.notifiedWaypoint = false
    Taxi.lastWaypointNotify = 0
    Taxi.vehicle = nil
    Taxi.driver = nil
end

local function cleanupTaxiInstant()
    deleteEntitySafe(Taxi.driver)
    deleteEntitySafe(Taxi.vehicle)
    resetTaxiState()
end

local function drawText3D(coords, text)
    local camCoords = GetGameplayCamCoords()
    local distance = #(coords - camCoords)
    if distance < 0.1 then distance = 0.1 end

    local scale = (Config.DrawTextScale / distance) * 2.0
    local fov = (1.0 / GetGameplayCamFov()) * 100.0
    scale = scale * fov

    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.0, scale)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end


setTaxiNuiVisible = function(state)
    SendNUIMessage({
        action = state and 'show' or 'hide'
    })
end

updateTaxiNui = function()
    SendNUIMessage({
        action = 'update',
        fare = Taxi.fareAmount or 0,
        km = string.format('%.2f', (Taxi.traveledMeters or 0.0) / 1000.0)
    })
end

local function getFreeRearSeat(vehicle)
    if GetPedInVehicleSeat(vehicle, 1) == 0 then return 1 end
    if GetPedInVehicleSeat(vehicle, 2) == 0 then return 2 end
    return nil
end

local function tryBoardTaxi()
    if not Taxi.active or not Taxi.vehicle or not DoesEntityExist(Taxi.vehicle) then return end
    local ped = PlayerPedId()
    if IsPedInVehicle(ped, Taxi.vehicle, false) then return end

    local seat = getFreeRearSeat(Taxi.vehicle)
    if not seat then
        notify('Non ci sono posti liberi sul taxi.', 'error')
        return
    end

    ClearPedTasks(ped)
    TaskEnterVehicle(ped, Taxi.vehicle, 5000, seat, 1.0, 1, 0)
end

local function getWaypointCoords()
    local blip = GetFirstBlipInfoId(8)
    if blip ~= 0 and DoesBlipExist(blip) then
        return GetBlipInfoIdCoord(blip)
    end
    return nil
end

local function getClosestRoadNode(coords)
    local found, outPos, outHeading = GetClosestVehicleNodeWithHeading(coords.x, coords.y, coords.z, 1, 3.0, 0)
    if found then
        return vec3(outPos.x, outPos.y, outPos.z), outHeading
    end
    return coords, GetEntityHeading(PlayerPedId())
end

local function setTaxiWaitingState()
    if not Taxi.vehicle or not DoesEntityExist(Taxi.vehicle) or not Taxi.driver or not DoesEntityExist(Taxi.driver) then return end

    if GetPedInVehicleSeat(Taxi.vehicle, -1) ~= Taxi.driver then
        SetPedIntoVehicle(Taxi.driver, Taxi.vehicle, -1)
        Wait(100)
    end

    ClearPedTasks(Taxi.driver)
    SetPedKeepTask(Taxi.driver, true)
    SetVehicleEngineOn(Taxi.vehicle, true, true, false)
    SetVehicleUndriveable(Taxi.vehicle, false)
    FreezeEntityPosition(Taxi.vehicle, false)
    SetVehicleHandbrake(Taxi.vehicle, false)
    BringVehicleToHalt(Taxi.vehicle, 2.5, 1500, false)
end

local function forceDriverDriveTo(dest)
    if not Taxi.vehicle or not DoesEntityExist(Taxi.vehicle) or not Taxi.driver or not DoesEntityExist(Taxi.driver) then return false end

    local vehicle = Taxi.vehicle
    local driver = Taxi.driver

    if GetPedInVehicleSeat(vehicle, -1) ~= driver then
        SetPedIntoVehicle(driver, vehicle, -1)
        Wait(150)
    end

    local roadDest = dest
    if Config.ForceRoadNodes then
        roadDest = getClosestRoadNode(dest)
    end

    ClearPedTasks(driver)
    SetPedKeepTask(driver, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleUndriveable(vehicle, false)
    FreezeEntityPosition(vehicle, false)
    SetVehicleHandbrake(vehicle, false)

    TaskVehicleDriveToCoord(
        driver,
        vehicle,
        roadDest.x,
        roadDest.y,
        roadDest.z,
        Config.MaxSpeedMs,
        0,
        GetEntityModel(vehicle),
        Config.CruiseDrivingStyle,
        Config.DriveStopRadius,
        true
    )

    return true
end

local function isPlayerReadyForDeparture()
    if not Taxi.vehicle or not DoesEntityExist(Taxi.vehicle) then return false end

    local playerPed = PlayerPedId()
    if not IsPedInVehicle(playerPed, Taxi.vehicle, false) then return false end

    local seat = getPlayerSeat(Taxi.vehicle)
    if seat ~= 1 and seat ~= 2 then return false end

    if not IsPedSittingInVehicle(playerPed, Taxi.vehicle) then return false end

    return GetPedInVehicleSeat(Taxi.vehicle, seat) == playerPed
end

local function waitUntilPlayerReadyForDeparture(timeoutMs)
    local expireAt = GetGameTimer() + (timeoutMs or 2500)

    while Taxi.active and Taxi.waitingWaypoint and GetGameTimer() < expireAt do
        if isPlayerReadyForDeparture() then
            return true
        end
        Wait(100)
    end

    return isPlayerReadyForDeparture()
end

local function addTaxiBlip(vehicle)
    removeTaxiBlip()
    Taxi.blip = AddBlipForEntity(vehicle)
    SetBlipSprite(Taxi.blip, Config.Blip.sprite)
    SetBlipColour(Taxi.blip, Config.Blip.color)
    SetBlipScale(Taxi.blip, Config.Blip.scale)
    SetBlipAsShortRange(Taxi.blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Blip.name)
    EndTextCommandSetBlipName(Taxi.blip)
end

local function getSpawnPointAroundPlayer(playerCoords)
    local found, outPos, outHeading

    for _ = 1, 25 do
        local angle = math.rad(math.random(0, 360))
        local distance = math.random(math.floor(Config.SpawnDistanceMin), math.floor(Config.SpawnDistanceMax)) + 0.0
        local probe = vec3(
            playerCoords.x + math.cos(angle) * distance,
            playerCoords.y + math.sin(angle) * distance,
            playerCoords.z
        )

        found, outPos, outHeading = GetClosestVehicleNodeWithHeading(probe.x, probe.y, probe.z, 1, 3.0, 0)
        if found then
            return outPos, outHeading
        end
    end

    return nil, nil
end

local function setupTaxiVehicle(vehicle, driver)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleHasBeenOwnedByPlayer(vehicle, false)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    SetVehicleIsStolen(vehicle, false)
    SetVehicleCanBreak(vehicle, false)
    SetVehicleCanLeakOil(vehicle, false)
    SetVehicleCanLeakPetrol(vehicle, false)
    SetVehicleStrong(vehicle, true)
    SetVehicleTyresCanBurst(vehicle, false)
    SetEntityInvincible(vehicle, true)

    SetPedCanBeDraggedOut(driver, false)
    SetPedStayInVehicleWhenJacked(driver, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedFleeAttributes(driver, 0, false)
    SetPedCombatAttributes(driver, 3, false)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.0)
    SetPedKeepTask(driver, true)
    SetEntityInvincible(driver, true)
    SetPedCanRagdoll(driver, false)
end

local function dismissTaxi()
    if not Taxi.active or Taxi.cancelling then return end
    Taxi.cancelling = true
    Taxi.fareActive = false

    if Taxi.fareAmount > 0 and not Taxi.hasCharged then
        Taxi.hasCharged = true
        TriggerServerEvent('bg_npctaxi:chargeFare', Taxi.fareAmount)
    end

    local playerPed = PlayerPedId()
    if Taxi.vehicle and DoesEntityExist(Taxi.vehicle) and IsPedInVehicle(playerPed, Taxi.vehicle, false) then
        TaskLeaveVehicle(playerPed, Taxi.vehicle, 0)
        local timeout = GetGameTimer() + 4000
        while IsPedInVehicle(playerPed, Taxi.vehicle, false) and GetGameTimer() < timeout do
            Wait(100)
        end
    end

    if Taxi.driver and DoesEntityExist(Taxi.driver) and Taxi.vehicle and DoesEntityExist(Taxi.vehicle) then
        if GetPedInVehicleSeat(Taxi.vehicle, -1) ~= Taxi.driver then
            SetPedIntoVehicle(Taxi.driver, Taxi.vehicle, -1)
            Wait(100)
        end

        local taxiPos = GetEntityCoords(Taxi.vehicle)
        local heading = GetEntityHeading(Taxi.vehicle)
        local ahead = vec3(
            taxiPos.x + math.cos(math.rad(heading)) * 220.0,
            taxiPos.y + math.sin(math.rad(heading)) * 220.0,
            taxiPos.z
        )

        ClearPedTasks(Taxi.driver)
        SetPedKeepTask(Taxi.driver, true)
        SetVehicleHandbrake(Taxi.vehicle, false)
        FreezeEntityPosition(Taxi.vehicle, false)
        SetVehicleUndriveable(Taxi.vehicle, false)
        SetVehicleEngineOn(Taxi.vehicle, true, true, false)

        local roadAhead = getClosestRoadNode(ahead)
        TaskVehicleDriveToCoord(Taxi.driver, Taxi.vehicle, roadAhead.x, roadAhead.y, roadAhead.z, Config.MaxSpeedMs, 0, GetEntityModel(Taxi.vehicle), Config.CruiseDrivingStyle, 20.0, true)
    end

    CreateThread(function()
        local timeout = GetGameTimer() + 25000
        while GetGameTimer() < timeout do
            Wait(1000)
            if not Taxi.vehicle or not DoesEntityExist(Taxi.vehicle) then break end
            local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(Taxi.vehicle))
            if dist >= Config.DeleteDistanceFromPlayer then break end
        end
        cleanupTaxiInstant()
    end)
end

local function finishRide(success)
    if not Taxi.active then return end

    if success then
        notify(('Corsa terminata. Totale: $%s'):format(Taxi.fareAmount), 'success')
    else
        notify(('Corsa interrotta. Totale: $%s'):format(Taxi.fareAmount), 'info')
    end

    dismissTaxi()
end

local function startFareMeter()
    Taxi.fareActive = true
    Taxi.traveledMeters = 0.0
    Taxi.fareAmount = Config.BaseFare

    CreateThread(function()
        local lastPos = GetEntityCoords(Taxi.vehicle)
        while Taxi.active and Taxi.fareActive and Taxi.vehicle and DoesEntityExist(Taxi.vehicle) do
            Wait(500)

            local currentPos = GetEntityCoords(Taxi.vehicle)
            local moved = #(currentPos - lastPos)
            lastPos = currentPos

            if moved > 0.5 and moved < 60.0 then
                Taxi.traveledMeters = Taxi.traveledMeters + moved
            end

            local wholeKm = math.floor(Taxi.traveledMeters / 1000.0)
            Taxi.fareAmount = Config.BaseFare + (wholeKm * Config.PricePerKm)
        end
    end)

    setTaxiNuiVisible(true)
    updateTaxiNui()

    CreateThread(function()
        while Taxi.active and Taxi.fareActive and Taxi.vehicle and DoesEntityExist(Taxi.vehicle) do
            Wait(0)
            updateTaxiNui()

            if IsControlJustPressed(0, Config.CancelKey) then
                SetVehicleDoorsLocked(Taxi.vehicle, 1)
                finishRide(false)
                break
            end
        end

        setTaxiNuiVisible(false)
    end)
end

local function waitForWaypointAndDrive()
    Taxi.waitingWaypoint = true
    Taxi.notifiedBoard = false
    Taxi.notifiedWaypoint = false
    Taxi.lastWaypointNotify = 0

    CreateThread(function()
        while Taxi.active and Taxi.waitingWaypoint do
            Wait(500)

            local playerPed = PlayerPedId()
            if not IsPedInVehicle(playerPed, Taxi.vehicle, false) then
                if not Taxi.notifiedBoard then
                    Taxi.notifiedBoard = true
                    notify('Il tassista ti aspetta. Premi E vicino al taxi per salire dietro.', 'info')
                end
            else
                local seat = getPlayerSeat(Taxi.vehicle)
                if seat == -1 or seat == 0 then
                    TaskLeaveVehicle(playerPed, Taxi.vehicle, 16)
                    notify('Puoi salire solo dietro.', 'error')
                    Wait(1000)
                else
                    local waypoint = getWaypointCoords()
                    if not waypoint then
                        if not Taxi.notifiedWaypoint or (GetGameTimer() - Taxi.lastWaypointNotify) >= 8000 then
                            Taxi.notifiedWaypoint = true
                            Taxi.lastWaypointNotify = GetGameTimer()
                            notify('Imposta un waypoint sulla mappa per partire.', 'info')
                        end
                    else
                        if not waitUntilPlayerReadyForDeparture(3000) then
                            notify('Aspetta di essere seduto bene dietro prima di partire.', 'error')
                            goto continue_waiting_for_waypoint
                        end

                        Taxi.waitingWaypoint = false
                        Taxi.rawDestination = waypoint
                        Taxi.destination = getClosestRoadNode(waypoint)
                        notify('Destinazione impostata. La corsa è iniziata.', 'success')
                        startFareMeter()
                        SetVehicleDoorsLocked(Taxi.vehicle, 4)
                        Wait(300)
                        forceDriverDriveTo(Taxi.destination)

                        CreateThread(function()
                            local stuckSince = nil

                            while Taxi.active and Taxi.destination do
                                Wait(1000)

                                if not DoesEntityExist(Taxi.vehicle) or not DoesEntityExist(Taxi.driver) then
                                    cleanupTaxiInstant()
                                    break
                                end

                                if GetPedInVehicleSeat(Taxi.vehicle, -1) ~= Taxi.driver then
                                    SetPedIntoVehicle(Taxi.driver, Taxi.vehicle, -1)
                                    Wait(300)
                                    forceDriverDriveTo(Taxi.destination)
                                end

                                SetVehicleEngineOn(Taxi.vehicle, true, true, false)
                                SetVehicleHandbrake(Taxi.vehicle, false)
                                FreezeEntityPosition(Taxi.vehicle, false)
                                SetVehicleUndriveable(Taxi.vehicle, false)

                                local vehicleCoords = GetEntityCoords(Taxi.vehicle)
                                local roadDist = #(vehicleCoords - Taxi.destination)
                                local rawDist = Taxi.rawDestination and #(vehicleCoords - Taxi.rawDestination) or roadDist
                                local speed = GetEntitySpeed(Taxi.vehicle)

                                if roadDist <= Config.DestinationStopDistance or rawDist <= (Config.DestinationStopDistance + 10.0) then
                                    Taxi.fareActive = false
                                    BringVehicleToHalt(Taxi.vehicle, 3.0, 1500, false)
                                    SetVehicleDoorsLocked(Taxi.vehicle, 1)
                                    Wait(1200)
                                    finishRide(true)
                                    break
                                end

                                if speed < 0.8 then
                                    if not stuckSince then
                                        stuckSince = GetGameTimer()
                                    elseif (GetGameTimer() - stuckSince) >= (Config.RepathIfStoppedSeconds * 1000) then
                                        debugPrint('Taxi bloccato, rilancio percorso')
                                        if GetPedInVehicleSeat(Taxi.vehicle, -1) ~= Taxi.driver then
                                            SetPedIntoVehicle(Taxi.driver, Taxi.vehicle, -1)
                                            Wait(200)
                                        end
                                        SetVehicleEngineOn(Taxi.vehicle, true, true, false)
                                        SetVehicleHandbrake(Taxi.vehicle, false)
                                        FreezeEntityPosition(Taxi.vehicle, false)
                                        SetVehicleUndriveable(Taxi.vehicle, false)
                                        forceDriverDriveTo(Taxi.destination)
                                        stuckSince = GetGameTimer()
                                    end
                                else
                                    stuckSince = nil
                                end
                            end
                        end)
                    end
                end
            end
            ::continue_waiting_for_waypoint::
        end
    end)
end

local function createTaxiRide()
    if Taxi.active then
        notify('Hai già un taxi attivo.', 'error')
        return
    end

    local allowed, reason = lib.callback.await('bg_npctaxi:canOrder', false)
    if not allowed then
        notify(reason or 'Non puoi chiamare un taxi adesso.', 'error')
        return
    end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    local spawnCoords, spawnHeading = getSpawnPointAroundPlayer(playerCoords)
    if not spawnCoords then
        notify('Non ho trovato una strada valida per far arrivare il taxi.', 'error')
        return
    end

    if not loadModel(Config.TaxiModel) or not loadModel(Config.DriverModel) then
        notify('Errore caricamento modelli del taxi.', 'error')
        return
    end

    local vehicle = CreateVehicle(Config.TaxiModel, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnHeading, true, false)
    local driver = CreatePedInsideVehicle(vehicle, 26, Config.DriverModel, -1, true, false)

    if vehicle == 0 or driver == 0 then
        notify('Impossibile creare il taxi.', 'error')
        deleteEntitySafe(driver)
        deleteEntitySafe(vehicle)
        return
    end

    Taxi.active = true
    Taxi.vehicle = vehicle
    Taxi.driver = driver

    setupTaxiVehicle(vehicle, driver)
    addTaxiBlip(vehicle)

    local pickupRoad = getClosestRoadNode(playerCoords)
    forceDriverDriveTo(pickupRoad)

    notify('Taxi in arrivo...', 'info')

    SetModelAsNoLongerNeeded(Config.TaxiModel)
    SetModelAsNoLongerNeeded(Config.DriverModel)

    CreateThread(function()
        local timeout = GetGameTimer() + 180000

        while Taxi.active and GetGameTimer() < timeout do
            Wait(500)

            if not DoesEntityExist(Taxi.vehicle) or not DoesEntityExist(Taxi.driver) then
                cleanupTaxiInstant()
                return
            end

            local currentPlayerCoords = GetEntityCoords(PlayerPedId())
            local taxiCoords = GetEntityCoords(Taxi.vehicle)
            local dist = #(currentPlayerCoords - taxiCoords)

            local pedVeh = GetVehiclePedIsIn(PlayerPedId(), false)
            if pedVeh == Taxi.vehicle then
                local seat = getPlayerSeat(Taxi.vehicle)
                if seat == -1 or seat == 0 then
                    TaskLeaveVehicle(PlayerPedId(), Taxi.vehicle, 16)
                    notify('Puoi salire solo dietro.', 'error')
                end
            end

            if not Taxi.waitingWaypoint and not Taxi.fareActive and dist <= Config.PlayerBoardDistance then
                setTaxiWaitingState()
                notify('Il taxi è arrivato. Premi E vicino al taxi per salire dietro e imposta una destinazione.', 'success')
                waitForWaypointAndDrive()
                return
            end
        end

        if Taxi.active then
            notify('Il taxi non è riuscito a raggiungerti.', 'error')
            cleanupTaxiInstant()
        end
    end)
end

RegisterCommand(Config.Command, function()
    createTaxiRide()
end, false)

CreateThread(function()
    while true do
        Wait(0)

        if Taxi.active and Taxi.vehicle and DoesEntityExist(Taxi.vehicle) then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local taxiCoords = GetEntityCoords(Taxi.vehicle)
            local dist = #(playerCoords - taxiCoords)

            if Taxi.waitingWaypoint and not IsPedInVehicle(playerPed, Taxi.vehicle, false) and dist <= 4.0 then
                if IsControlJustPressed(0, 38) then
                    tryBoardTaxi()
                end
            end

            if IsPedInVehicle(playerPed, Taxi.vehicle, false) then
                local seat = getPlayerSeat(Taxi.vehicle)
                if seat == -1 or seat == 0 then
                    TaskLeaveVehicle(playerPed, Taxi.vehicle, 16)
                    notify('Puoi salire solo dietro.', 'error')
                    Wait(1000)
                end
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    setTaxiNuiVisible(false)
    cleanupTaxiInstant()
end)
