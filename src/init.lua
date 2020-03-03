local BitBuffer = require(script.BitBuffer)
local BitEncodeInstance = require(script.BitEncodeInstance)

local InstanceEncoder = {}

--[[**
	Encodes an Instance and its descendants into a Base64 string.

	@param {t:Instance} Instance The Instance you are encoding.
	@returns {t:string} The Base64 encoded string that represents the Instance and its descendants.
**--]]
function InstanceEncoder.Encode(Instance)
	local Buffer = BitBuffer.new()
	BitEncodeInstance.Write(Buffer, Instance)
	return Buffer:ToBase64()
end

--[[**
	Encodes an Instance and its descendants into a Base128 string.

	@param {t:Instance} Instance The Instance you are encoding.
	@returns {t:string} The Base128 encoded string that represents the Instance and its descendants.
**--]]
function InstanceEncoder.Encode128(Instance)
	local Buffer = BitBuffer.new()
	BitEncodeInstance.Write(Buffer, Instance)
	return Buffer:ToBase128()
end

--[[**
	Decodes a Base64 string that was returned from the `InstanceEncoder.Encode` function and creates an Instance from it.

	@param {t:string} Base64 The Base64 string returned from calling `InstanceEncoder.Encode`.
	@returns {t:Instance} The Instance that was encoded.
**--]]
function InstanceEncoder.Decode(Base64)
	local Buffer = BitBuffer.new()
	Buffer:FromBase64(Base64)
	return BitEncodeInstance.Read(Buffer)
end

--[[**
	Decodes a Base128 string that was returned from the `InstanceEncoder.Encode128` function and creates an Instance from it.

	@param {t:string} Base128 The Base128 string returned from calling `InstanceEncoder.Encode128`.
	@returns {t:Instance} The Instance that was encoded.
**--]]
function InstanceEncoder.Decode128(Base128)
	local Buffer = BitBuffer.new()
	Buffer:FromBase128(Base128)
	return BitEncodeInstance.Read(Buffer)
end

return InstanceEncoder