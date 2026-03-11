local cmds = require('commands')
local getopt = require('getopt')
local bin = require('bin')
local ansicolors = require('ansicolors')

copyright = ''
author = 'Codex'
version = 'v1.0.0'
desc = [[
Hammer the real SEOS SAM PACS path over CMD_HF_SAM_SEOS against a SAM module and SEOS card.
This validates that repeated PACS requests do not wedge the PM3 with trace enabled or disabled.
]]
example = [[
    1. script run tests/hf_seos_sam_hammer -i 500
    2. script run tests/hf_seos_sam_hammer -i 500 -n
]]
usage = [[
script run tests/hf_seos_sam_hammer [-h] [-i <iterations>] [-n] [-k] [-s] [-d <hex>]
]]
arguments = [[
    -h             : this help
    -i <dec>       : number of SEOS SAM requests to send, default 500
    -n             : disable PM3 trace for this session
    -k             : keep RF field active between iterations
    -s             : skip detect after the first successful iteration
    -d <hex>       : DER encoded request to send to SAM, default uses firmware PACS request
]]

local DEFAULT_ITERATIONS = 500

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
    return nil, msg
end

local function build_payload(flags, request_hex)
    if request_hex ~= nil and #request_hex > 0 then
        return string.char(flags) .. bin.pack('H', request_hex)
    end
    return string.char(flags)
end

local function send_seos(flags, request_hex)
    local command = Command:newNG{
        cmd = cmds.CMD_HF_SAM_SEOS,
        data = build_payload(flags, request_hex)
    }
    local response, err = command:sendNG(false, 5000)
    if response == nil then
        return nil, err or 'no response'
    end
    return response, nil
end

local function main(args)
    local iterations = DEFAULT_ITERATIONS
    local no_trace = false
    local keep_field = true
    local skip_detect_after_first = true
    local request_hex = ''

    for o, arg in getopt.getopt(args, 'hi:nksd:') do
        if o == 'h' then
            return help()
        elseif o == 'i' then
            iterations = tonumber(arg)
        elseif o == 'n' then
            no_trace = true
        elseif o == 'k' then
            keep_field = true
        elseif o == 's' then
            skip_detect_after_first = true
        elseif o == 'd' then
            request_hex = arg:upper()
        end
    end

    if iterations == nil or iterations < 1 then
        return fail('iterations must be >= 1')
    end
    if (#request_hex % 2) ~= 0 then
        return fail('DER request hex length must be even')
    end

    print(('SEOS SAM hammer start: iterations=%d trace=%s keep=%s skip_detect_after_first=%s'):format(
        iterations,
        no_trace and 'off' or 'on',
        keep_field and 'yes' or 'no',
        skip_detect_after_first and 'yes' or 'no'
    ))

    for i = 1, iterations do
        if core.kbd_enter_pressed() then
            return fail('aborted by user')
        end

        local flags = 0
        if not keep_field then
            flags = flags + 0x01
        end
        if skip_detect_after_first and i > 1 then
            flags = flags + 0x02
        end
        if no_trace then
            flags = flags + 0x04
        end

        local response, err = send_seos(flags, request_hex)
        if response == nil then
            return fail(('iteration %d transport failed: %s'):format(i, err or 'unknown error'))
        end
        if response.Status ~= 0 then
            return fail(('iteration %d firmware status %d'):format(i, response.Status))
        end
        if response.Data == nil or #response.Data == 0 then
            return fail(('iteration %d returned empty response'):format(i))
        end

        print(('iter %d/%d ok len=%d skip_detect=%s trace=%s'):format(
            i,
            iterations,
            #response.Data,
            (skip_detect_after_first and i > 1) and 'yes' or 'no',
            no_trace and 'off' or 'on'
        ))
    end

    local final_flags = 0
    if not keep_field then
        final_flags = final_flags + 0x01
    end
    if skip_detect_after_first then
        final_flags = final_flags + 0x02
    end
    if no_trace then
        final_flags = final_flags + 0x04
    end

    local final_response, final_err = send_seos(final_flags, request_hex)
    if final_response == nil then
        return fail('post-loop request failed: ' .. (final_err or 'unknown error'))
    end
    if final_response.Status ~= 0 or final_response.Data == nil or #final_response.Data == 0 then
        return fail(('post-loop request returned invalid result (status=%d len=%d)'):format(
            final_response.Status or -1,
            final_response.Data and #final_response.Data or 0
        ))
    end

    print(('HAMMER PASS: iterations=%d trace=%s'):format(iterations, no_trace and 'off' or 'on'))
end

main(args)
