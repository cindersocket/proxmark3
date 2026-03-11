local cmds = require('commands')
local getopt = require('getopt')
local bin = require('bin')
local lib14a = require('read14a')
local ansicolors = require('ansicolors')

copyright = ''
author = 'Codex'
version = 'v1.0.0'
desc = [[
Hammer the ISO14443-A APDU path against a DESFire card to validate long-running reader sessions.
This is intended as a hardware regression test for trace saturation and no-trace sessions.
]]
example = [[
    1. script run tests/hf_14a_desfire_hammer -i 500
    2. script run tests/hf_14a_desfire_hammer -i 500 -n
]]
usage = [[
script run tests/hf_14a_desfire_hammer [-h] [-i <iterations>] [-n] [-r <count>]
]]
arguments = [[
    -h             : this help
    -i <dec>       : number of wrapped DESFire GetVersion APDUs to send, default 500
    -n             : disable PM3 trace for this session
    -r <dec>       : reconnect every N iterations, default 0 keeps one reader session open
]]

local DEFAULT_ITERATIONS = 500
local APDU_GET_VERSION = '9060000000'
local APDU_GET_MORE = '90AF000000'

local band = bit32.band

local function help()
    print(copyright)
    print(author)
    print(version)
    print(desc)
    print(ansicolors.cyan .. 'Usage' .. ansicolors.reset)
    print(usage)
    print(ansicolors.cyan .. 'Arguments' .. ansicolors.reset)
    print(arguments)
    print(ansicolors.cyan .. 'Example usage' .. ansicolors.reset)
    print(example)
end

local function fail(msg)
    print('HAMMER FAIL: ' .. msg)
    lib14a.disconnect()
    return nil, msg
end

local function unpack_ack(result)
    local _, _, arg0, arg1, data = bin.unpack('LLLLH', result)
    if arg0 > 0x7FFFFFFF then
        arg0 = arg0 - 0x100000000
    end
    local payload = ''
    if arg0 > 0 then
        payload = data:sub(1, arg0 * 2)
    end
    return arg0, band(arg1, 0xFF), payload
end

local function send_apdu_frame(apdu_hex, connect, no_trace)
    local flags = lib14a.ISO14A_COMMAND.ISO14A_APDU + lib14a.ISO14A_COMMAND.ISO14A_NO_DISCONNECT
    if connect then
        flags = flags + lib14a.ISO14A_COMMAND.ISO14A_CONNECT
    end
    if no_trace then
        flags = flags + lib14a.ISO14A_COMMAND.ISO14A_NO_TRACE
    end

    local command = Command:newMIX{
        cmd = cmds.CMD_HF_ISO14443A_READER,
        arg1 = flags,
        arg2 = #apdu_hex / 2,
        data = apdu_hex
    }

    return command:sendMIX(false, 5000)
end

local function exchange_apdu(apdu_hex, connect, no_trace)
    local response = ''
    local frame = apdu_hex
    local need_connect = connect

    while true do
        local result, err = send_apdu_frame(frame, need_connect, no_trace)
        if not result then
            return fail(err or 'device did not acknowledge APDU frame')
        end

        local len, pcb, payload = unpack_ack(result)
        if len < 0 then
            return fail(('firmware returned error %d'):format(len))
        end
        if len > 0 then
            response = response .. payload
        end
        if band(pcb, 0x10) == 0 then
            return response, nil
        end

        frame = ''
        need_connect = false
    end
end

local function exchange_desfire_get_version(connect, no_trace)
    local response, err = exchange_apdu(APDU_GET_VERSION, connect, no_trace)
    if not response then
        return nil, err
    end

    while #response >= 4 and response:sub(-4) == '91AF' do
        local more_response
        more_response, err = exchange_apdu(APDU_GET_MORE, false, no_trace)
        if not more_response then
            return nil, err
        end

        response = response .. more_response
    end

    return response, nil
end

local function main(args)
    local iterations = DEFAULT_ITERATIONS
    local no_trace = false
    local reselect_every = 0

    for o, arg in getopt.getopt(args, 'hi:nr:') do
        if o == 'h' then
            return help()
        elseif o == 'i' then
            iterations = tonumber(arg)
        elseif o == 'n' then
            no_trace = true
        elseif o == 'r' then
            reselect_every = tonumber(arg)
        end
    end

    if iterations == nil or iterations < 1 then
        return fail('iterations must be >= 1')
    end
    if reselect_every == nil or reselect_every < 0 then
        return fail('reselect count must be >= 0')
    end

    print(('DESFire hammer start: iterations=%d trace=%s reselect_every=%d'):format(
        iterations,
        no_trace and 'off' or 'on',
        reselect_every
    ))

    for i = 1, iterations do
        if core.kbd_enter_pressed() then
            return fail('aborted by user')
        end

        local connect = (i == 1)
        if reselect_every > 0 and i > 1 and ((i - 1) % reselect_every == 0) then
            lib14a.disconnect()
            connect = true
        end

        local response, err = exchange_desfire_get_version(connect, no_trace)
        if not response then
            return nil, err
        end
        if #response < 4 then
            return fail(('iteration %d returned a short APDU response'):format(i))
        end

        local sw = response:sub(-4)
        if sw ~= '9100' then
            return fail(('iteration %d returned DESFire status %s'):format(i, sw))
        end

        print(('iter %d/%d ok len=%d sw=%s'):format(i, iterations, #response / 2, sw))
    end

    lib14a.disconnect()
    print(('HAMMER PASS: iterations=%d trace=%s'):format(iterations, no_trace and 'off' or 'on'))
end

main(args)
