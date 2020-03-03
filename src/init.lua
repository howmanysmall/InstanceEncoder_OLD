local BitBuffer = require(script.BitBuffer)
local BitEncodeInstance = require(script.BitEncodeInstance)

local InstanceEncoder = {}

function InstanceEncoder.Encode(Instance)
	local Buffer = BitBuffer.new()
	BitEncodeInstance.Write(Buffer, Instance)
	return Buffer:ToBase64()
end

function InstanceEncoder.Encode128(Instance)
	local Buffer = BitBuffer.new()
	BitEncodeInstance.Write(Buffer, Instance)
	return Buffer:ToBase128()
end

function InstanceEncoder.Decode(Base64)
	local Buffer = BitBuffer.new()
	Buffer:FromBase64(Base64)
	return BitEncodeInstance.Read(Buffer)
end

function InstanceEncoder.Decode128(Base128)
	local Buffer = BitBuffer.new()
	Buffer:FromBase128(Base128)
	return BitEncodeInstance.Read(Buffer)
end

return InstanceEncoder