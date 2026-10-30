StatCapsItemLinks = {};

local function decode(encoded)
    if (#encoded > 32768) then error("Item link is too large."); end
    local bytes = {};
    for lead, tail in encoded:gmatch("([\196-\199])([\128-\191])") do
        bytes[#bytes + 1] = (lead:byte() - 196) * 64 + tail:byte() - 128;
    end
    if (#bytes * 2 ~= #encoded or #bytes < 14) then error("Invalid item-link encoding."); end
    local function uint(i)
        return bytes[i] + bytes[i + 1] * 256 + bytes[i + 2] * 65536 + bytes[i + 3] * 16777216;
    end
    if (uint(1) ~= 0) then error("Unsupported item-link header."); end
    local expected = uint(5);
    if (expected < 12 or expected > 65536) then error("Invalid item-link size."); end
    local cmf, flags = bytes[9], bytes[10];
    if (cmf % 16 ~= 8 or math.floor(cmf / 16) > 7 or
        (cmf * 256 + flags) % 31 ~= 0 or math.floor(flags / 32) % 2 ~= 0) then
        error("Unsupported compressed item link.");
    end
    local position, bit = 11, 0;
    local function read(count)
        local value = 0;
        for i = 0, count - 1 do
            if (position > #bytes - 4) then error("Truncated item link."); end
            value = value + math.floor(bytes[position] / 2 ^ bit) % 2 * 2 ^ i;
            bit = bit + 1;
            if (bit == 8) then bit, position = 0, position + 1; end
        end
        return value;
    end
    local function tree(lengths)
        local counts, nextCode, codes, maximum = {}, {}, {}, 0;
        for _, length in ipairs(lengths) do
            counts[length] = (counts[length] or 0) + 1;
            maximum = math.max(maximum, length);
        end
        local code = 0;
        for length = 1, maximum do
            code = (code + (length > 1 and counts[length - 1] or 0)) * 2;
            if (code + (counts[length] or 0) > 2 ^ length) then error("Invalid Huffman tree."); end
            nextCode[length], codes[length] = code, {};
        end
        for index, length in ipairs(lengths) do
            if (length > 0) then
                codes[length][nextCode[length]] = index - 1;
                nextCode[length] = nextCode[length] + 1;
            end
        end
        return function()
            local value = 0;
            for length = 1, maximum do
                value = value * 2 + read(1);
                if (codes[length][value] ~= nil) then return codes[length][value]; end
            end
            error("Invalid Huffman symbol.");
        end;
    end
    local output = {};
    local function emit(value)
        if (#output >= expected) then error("Item link exceeds declared size."); end
        output[#output + 1] = value;
    end
    local lengthBase = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
    local lengthExtra = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
    local distanceBase = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
    local distanceExtra = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};
    local final;
    repeat
        final = read(1);
        local kind = read(2);
        if (kind == 0) then
            if (bit ~= 0) then bit, position = 0, position + 1; end
            local size, inverse = read(16), read(16);
            if (size + inverse ~= 65535) then error("Invalid stored block."); end
            for _ = 1, size do emit(read(8)); end
        elseif (kind == 1 or kind == 2) then
            local literals, distances = {}, {};
            if (kind == 1) then
                for symbol = 0, 287 do
                    literals[symbol + 1] = symbol < 144 and 8 or symbol < 256 and 9 or symbol < 280 and 7 or 8;
                end
                for i = 1, 32 do distances[i] = 5; end
            else
                local literalCount, distanceCount, codeCount = read(5) + 257, read(5) + 1, read(4) + 4;
                if (literalCount > 286) then error("Invalid Huffman tree."); end
                local order = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
                local codeLengths = {};
                for i = 1, 19 do codeLengths[i] = 0; end
                for i = 1, codeCount do codeLengths[order[i] + 1] = read(3); end
                local symbol, lengths = tree(codeLengths), {};
                while (#lengths < literalCount + distanceCount) do
                    local value = symbol();
                    if (value < 16) then lengths[#lengths + 1] = value;
                    else
                        local repeatCount, repeated;
                        if (value == 16) then
                            if (#lengths == 0) then error("Invalid repeated length."); end
                            repeatCount, repeated = read(2) + 3, lengths[#lengths];
                        elseif (value == 17) then repeatCount, repeated = read(3) + 3, 0;
                        else repeatCount, repeated = read(7) + 11, 0; end
                        if (#lengths + repeatCount > literalCount + distanceCount) then error("Too many code lengths."); end
                        for _ = 1, repeatCount do lengths[#lengths + 1] = repeated; end
                    end
                end
                for i = 1, literalCount do literals[i] = lengths[i]; end
                for i = 1, distanceCount do distances[i] = lengths[literalCount + i]; end
            end
            if (not literals[257] or literals[257] == 0) then error("Missing end marker."); end
            local literal, distance = tree(literals), tree(distances);
            while (true) do
                local symbol = literal();
                if (symbol == 256) then break;
                elseif (symbol < 256) then emit(symbol);
                else
                    local index = symbol - 256;
                    if (not lengthBase[index]) then error("Invalid length symbol."); end
                    local length = lengthBase[index] + read(lengthExtra[index]);
                    local d = distance() + 1;
                    if (not distanceBase[d]) then error("Invalid distance symbol."); end
                    local offset = distanceBase[d] + read(distanceExtra[d]);
                    if (offset > #output) then error("Invalid back-reference."); end
                    for _ = 1, length do emit(output[#output - offset + 1]); end
                end
            end
        else error("Invalid compression block."); end
    until final == 1;
    if (bit ~= 0) then position = position + 1; end
    if (#output ~= expected or position ~= #bytes - 3) then error("Item-link size mismatch."); end
    local a, b = 1, 0;
    for _, value in ipairs(output) do a = (a + value) % 65521; b = (b + a) % 65521; end
    local checksum = bytes[position] * 16777216 + bytes[position + 1] * 65536 + bytes[position + 2] * 256 + bytes[position + 3];
    if (b * 65536 + a ~= checksum) then error("Item-link checksum mismatch."); end
    bytes = output;
    local itemLevel;
    for i = 13, #bytes - 7 do
        if (uint(i) == 268437097) then
            local value = uint(i + 4);
            if (value >= 1 and value <= 999) then
                if (itemLevel and itemLevel ~= value) then error("Conflicting item levels."); end
                itemLevel = value;
            end
        end
    end
    return { id = uint(9), level = itemLevel };
end

function StatCapsItemLinks.Parse(text)
    if (type(text) ~= "string" or #text > 33000) then return nil, "Invalid item link."; end
    local id = text:match("^<Examine:IIDDID:0x%x+:0x(%x+)>%[[^<>]-%]<\\Examine>$");
    if (id) then
        if (#id > 8 or tonumber(id, 16) == 0) then return nil, "Invalid item link."; end
        return { id = tonumber(id, 16) };
    end
    local encoded = text:match("^<ExamineItemInstance:ItemInfo:(.-)>%[[^<>]-%]<\\ExamineItemInstance>$");
    if (not encoded) then return nil, "Unsupported item link. Use a normal item link or enter its numeric ID."; end
    local ok, result = pcall(decode, encoded);
    if (not ok) then return nil, "Cannot decode item link: " .. tostring(result); end
    return result;
end
