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
    local count, _, arg0, arg1, arg2 = bin.unpack('LLLL', result)
    local payload = ''

    if arg0 > 0 then
        payload = string.sub(result, count, count + arg0 - 1)
    end

    if arg0 > 0x7FFFFFFF then
        arg0 = arg0 - 0x100000000
    end

    return arg0, arg1, arg2, payload
end

local function send_apdu_frame(apdu_hex, connect, no_trace)
    local flags = lib14a.ISO14A_COMMAND.ISO14A_APDU + lib14a.ISO14A_COMMAND.ISO14A_NO_DISCONNECT
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

local function connect_card(no_trace, iteration)
    local extra_flags = 0
    if no_trace then
        extra_flags = lib14a.ISO14A_COMMAND.ISO14A_NO_TRACE
    end

    local info, err = lib14a.read(true, false, extra_flags)
    if not info then
        return fail(('iteration %d select failed: %s'):format(iteration, err or 'no card in field'))
    end

    return true, nil
end

local function exchange_apdu(apdu_hex, connect, no_trace)
    local result, err = send_apdu_frame(apdu_hex, connect, no_trace)
    if not result then
        return nil, err or 'device did not acknowledge APDU frame'
    end

    local len, status, _, payload = unpack_ack(result)
    if len < 0 then
        return nil, ('firmware returned error %d'):format(len)
    end
    if len < 2 then
        return nil, ('short APDU frame len=%d status=%d'):format(len, status)
    end

    return payload, nil
end

local function response_hex(response)
    local out = {}
    for i = 1, #response do
        out[i] = ('%02X'):format(string.byte(response, i))
    end
    return table.concat(out)
end

local function response_without_crc(response)
    local len = #response
    if len < 2 then
        return nil
    end

    return string.sub(response, 1, len - 2)
end

local function response_sw(response)
    local payload = response_without_crc(response)
    if payload == nil then
        return nil
    end

    local len = #payload
    if len < 2 then
        return nil
    end

    return ('%02X%02X'):format(string.byte(payload, len - 1), string.byte(payload, len))
end

local function payload_sw(payload)
    local len = #payload
    if len < 2 then
        return nil
    end

    return ('%02X%02X'):format(string.byte(payload, len - 1), string.byte(payload, len))
end

local function expect_status(response, expected_sw, iteration, step)
    if #response < 4 then
        return fail(('iteration %d step %d returned a short APDU response'):format(iteration, step))
    end

    local sw = response_sw(response)
    if sw ~= expected_sw then
        return fail(('iteration %d step %d returned DESFire status %s payload=%s'):format(
            iteration,
            step,
            sw,
            response_hex(response)
        ))
    end

    return true, nil
end

local function exchange_desfire_get_version(connect, no_trace, iteration)
    local response1, err = exchange_apdu(APDU_GET_VERSION, connect, no_trace)
    if not response1 then
        return fail(('iteration %d step 1 failed: %s'):format(iteration, err))
    end
    local ok = expect_status(response1, '91AF', iteration, 1)
    if not ok then
        return nil, 'unexpected DESFire continuation status'
    end

    local response2
    response2, err = exchange_apdu(APDU_GET_MORE, false, no_trace)
    if not response2 then
        return fail(('iteration %d step 2 failed: %s'):format(iteration, err))
    end
    ok = expect_status(response2, '91AF', iteration, 2)
    if not ok then
        return nil, 'unexpected DESFire continuation status'
    end

    local response3
    response3, err = exchange_apdu(APDU_GET_MORE, false, no_trace)
    if not response3 then
        return fail(('iteration %d step 3 failed: %s'):format(iteration, err))
    end
    ok = expect_status(response3, '9100', iteration, 3)
    if not ok then
        return nil, 'unexpected DESFire final status'
    end

    local response = response_without_crc(response1) .. response_without_crc(response2) .. response_without_crc(response3)
    if #response < 9 then
        return fail(('iteration %d returned a short concatenated DESFire response (%d bytes)'):format(
            iteration,
            #response
        ))
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

        if connect then
            local ok, err = connect_card(no_trace, i)
            if not ok then
                return nil, err
            end
        end

        local response, err = exchange_desfire_get_version(connect, no_trace, i)
        if not response then
            return nil, err
        end

        local sw = payload_sw(response)
        print(('iter %d/%d ok len=%d sw=%s'):format(i, iterations, #response, sw))
    end

    lib14a.disconnect()
    print(('HAMMER PASS: iterations=%d trace=%s'):format(iterations, no_trace and 'off' or 'on'))
end

main(args)
