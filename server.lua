local ESX = exports.es_extended:getSharedObject()

lib.callback.register('bg_npctaxi:canOrder', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Player non valido.' end

    local bank = xPlayer.getAccount('bank')
    local bankMoney = bank and bank.money or 0

    if bankMoney < Config.MinimumBankToOrder then
        return false, ('Ti servono almeno $%s in banca per chiamare un taxi.'):format(Config.MinimumBankToOrder)
    end

    return true
end)

RegisterNetEvent('bg_npctaxi:chargeFare', function(amount)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local bank = xPlayer.getAccount('bank')
    local bankMoney = bank and bank.money or 0

    if bankMoney >= amount then
        xPlayer.removeAccountMoney('bank', amount, 'NPC Taxi fare')
        TriggerClientEvent('esx:showNotification', src, ('Hai pagato $%s dal conto bancario.'):format(amount), 'success')
    else
        if bankMoney > 0 then
            xPlayer.removeAccountMoney('bank', bankMoney, 'NPC Taxi partial fare')
        end

        TriggerClientEvent('esx:showNotification', src, ('Saldo insufficiente. Addebitati $%s su $%s.'):format(bankMoney, amount), 'error')
    end
end)
