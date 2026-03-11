local cmds = require('commands')
local getopt = require('getopt')
local bin = require('bin')
local ansicolors = require('ansicolors')

copyright = ''
author = 'Codex'
version = 'v1.0.0'
desc = [[
Hammer the smartcard raw APDU path over CMD_SMART_RAW while keeping one session open.
This is intended to validate trace saturation and no-trace operation for the PM3 smartcard module.
]]
example = [[
    1. script run tests/smartcard_trace_hammer -i 500
    2. script run tests/smartcard_trace_hammer -i 500 -n
]]
usage = [[
script run tests/smartcard_trace_hammer [-h] [-i <iterations>] [-n] [-a <hex>] [-w <sw>] [-t <ms>]
]]
arguments = [[
    -h             : this help
    -i <dec>       : number of APDUs to send, default 500
    -n             : disable PM3 trace for this session
    -a <hex>       : APDU to transmit, default 00A404000E315041592E5359532E444446303100
    -w <hex>       : expected status word, default 9000
    -t <dec>       : wait timeout in ms, default 337
]]

local DEFAULT_ITERATIONS = 500
local DEFAULT_TIMEOUT_MS = 337
local DEFAULT_APDU = '00A404000E315041592E5359532E444446303100'
local DEFAULT_SW = '9000'

local SC_CONNECT = 0x0001
local SC_RAW = 0x0004
local SC_SELECT = 0x0008
local SC_RAW_T0 = 0x0010
local SC_CLEARLOG = 0x0020
local SC_LOG = 0x0040
local SC_WAIT = 0x0080
local SC_NO_TRACE = 0x0100

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

local function le16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function le32(n)
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

local function fail(msg)
    print('HAMMER FAIL: ' .. msg)
    return nil, msg
end

local function build_payload(flags, wait_ms, apdu_hex)
    local data = ''
    if apdu_hex ~= nil and #apdu_hex > 0 then
        data = bin.pack('H', apdu_hex)
    end
    return le16(flags) .. le32(wait_ms) .. le16(#data) .. data
end

local function send_smartcard(flags, wait_ms, apdu_hex)
    local command = Command:newNG{
        cmd = cmds.CMD_SMART_RAW,
        data = build_payload(flags, wait_ms, apdu_hex)
    }
    local response, err = command:sendNG(false, 4000)
    if response == nil then
        return nil, err or 'no response'
    end
    if response.Status ~= 0 then
        return nil, ('firmware status %d'):format(response.Status)
    end
    return response.Data, nil
end

local function status_word(resp)
    local len = #resp
    if len < 2 then
        return nil
    end
    return ('%02X%02X'):format(string.byte(resp, len - 1), string.byte(resp, len))
end

local function main(args)
    local iterations = DEFAULT_ITERATIONS
    local no_trace = false
    local apdu = DEFAULT_APDU
    local expected_sw = DEFAULT_SW
    local timeout_ms = DEFAULT_TIMEOUT_MS

    for o, arg in getopt.getopt(args, 'hi:na:w:t:') do
        if o == 'h' then
            return help()
        elseif o == 'i' then
            iterations = tonumber(arg)
        elseif o == 'n' then
            no_trace = true
        elseif o == 'a' then
            apdu = arg:upper()
        elseif o == 'w' then
            expected_sw = arg:upper()
        elseif o == 't' then
            timeout_ms = tonumber(arg)
        end
    end

    if iterations == nil or iterations < 1 then
        return fail('iterations must be >= 1')
    end
    if timeout_ms == nil or timeout_ms < 0 then
        return fail('timeout must be >= 0')
    end
    if (#apdu % 2) ~= 0 then
        return fail('APDU hex length must be even')
    end
    if expected_sw ~= nil and #expected_sw > 0 and #expected_sw ~= 4 then
        return fail('expected SW must be 4 hex characters')
    end

    print(('Smartcard hammer start: iterations=%d trace=%s timeout_ms=%d'):format(
        iterations,
        no_trace and 'off' or 'on',
        timeout_ms
    ))

    for i = 1, iterations do
        if core.kbd_enter_pressed() then
            return fail('aborted by user')
        end

        local flags = SC_RAW_T0 + SC_WAIT
        if no_trace then
            flags = flags + SC_NO_TRACE
        else
            flags = flags + SC_LOG
        end
        if i == 1 then
            flags = flags + SC_CONNECT + SC_SELECT + SC_CLEARLOG
        end

        local response, err = send_smartcard(flags, timeout_ms, apdu)
        if response == nil then
            return fail(('iteration %d failed: %s'):format(i, err or 'unknown error'))
        end
        if #response < 2 then
            return fail(('iteration %d returned short response'):format(i))
        end

        local sw = status_word(response)
        if expected_sw ~= nil and #expected_sw > 0 and sw ~= expected_sw then
            return fail(('iteration %d returned SW %s, expected %s'):format(i, sw, expected_sw))
        end

        print(('iter %d/%d ok len=%d sw=%s'):format(i, iterations, #response, sw))
    end

    print(('HAMMER PASS: iterations=%d trace=%s'):format(iterations, no_trace and 'off' or 'on'))
end

main(args)
