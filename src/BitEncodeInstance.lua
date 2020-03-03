local Generators = require(script.Parent.Generators)
local MDClass = Generators.GenerateMDClass()
local MDEnum = Generators.GenerateMDEnum()

-- To-do: Make this work!
-- Issue: The generated stuff seems to be missing classes? I don't know.

local BitEncodeInstance = {}
local CachedMDClass = {}

local ipairs = ipairs
local next = next

local IgnorePropertySet = {
	["BasePart::BrickColor"] = true;
}

local TypeAlias = {
	Content = "string";
	ProtectedString = "string";
}

local IdToClass = {}
local ClassIdWidth, ClassIdWidthWidth

do
	local ClassId = 0
	for _, Class in next, MDClass do
		Class.Id = ClassId
		IdToClass[ClassId] = Class
		ClassId = ClassId + 1

		local PropertyId = 0
		local PropertyList = {}
		for _, Property in next, Class.PropertyMap do
			Property.Id = PropertyId
			PropertyId = PropertyId + 1
			PropertyList[PropertyId] = Property
		end

		local PropertyIdBits = math.ceil(math.log(PropertyId + 1) / 0.69314718055995)
		Class.PropertyList = PropertyList
		for _, Property in next, Class.PropertyMap do
			Property.IdWidth = PropertyIdBits
		end
	end

	ClassIdWidth = math.ceil(math.log(ClassId + 1) / 0.69314718055995)
	ClassIdWidthWidth = math.ceil(math.log(ClassIdWidth + 1) / 0.69314718055995)
end

do
	for _, Enumeration in next, MDEnum do
		local IdGen = 0
		local ValueToId = {}
		local ValueArray = {}

		for Value in next, Enumeration.ValueMap do
			local RobloxValue = Enum[Enumeration.EnumName][Value]
			ValueToId[RobloxValue] = IdGen
			IdGen = IdGen + 1
			ValueArray[IdGen] = RobloxValue
		end

		Enumeration.ValueToId = ValueToId
		Enumeration.ValueArray = ValueArray
		Enumeration.BitWidth = math.ceil(math.log((IdGen - 1) + 1) / 0.69314718055995)
	end
end

local DEFAULT_TABLE = {
	PropertyMap = {Name = {Writeonly = true, Security = "PluginSecurity"}};
}

local function GetPropertyList(ClassName)
	local Properties = CachedMDClass[ClassName]
	if not Properties then
		Properties = {}
		local Length = 0
		local MdClass = MDClass[ClassName]

		if not MdClass then
			MdClass = DEFAULT_TABLE
--			print(ClassName, "is lacking!")
		end

		for _, Property in next, MdClass.PropertyMap do
			if not Property.Writeonly and not Property.Readonly and Property.Security ~= "PluginSecurity" then
				local PropertyName = Property.PropertyName
				local PropertyType = Property.PropertyType

				local PropertyData = {
					Name = PropertyName;
					Type = TypeAlias[PropertyType] or PropertyType;
					NSName = MdClass.ClassName .. "::" .. PropertyName;
					Property = Property;
					PropertyId = Property.Id;
					PropertyIdWidth = Property.IdWidth;
					Class = MdClass;
					ClassId = MdClass.Id;
					InstanceCount = 0;
				}

				if not IgnorePropertySet[PropertyData.NSName] then
					Length = Length + 1
					Properties[Length] = PropertyData
				end
			end
		end

		local BaseMDClass = MdClass.BaseClassName
		if BaseMDClass then
			for _, Property in ipairs(GetPropertyList(BaseMDClass)) do
				Length = Length + 1
				Properties[Length] = Property
			end
		end

		CachedMDClass[ClassName] = Properties
	end

	return Properties
end

local HashValueLookup = {
	string = function(Value)
		return "s_" .. Value
	end;

	float = function(Value)
		return "f_" .. Value
	end;

	double = function(Value)
		return "d_" .. Value
	end;

	int = function(Value)
		return "i_" .. Value
	end;

	bool = function(Value)
		return "b_" .. tostring(Value)
	end;

	Vector3 = function(Value)
		return "V_" .. tostring(Value)
	end;

	Vector2 = function(Value)
		return "2_" .. tostring(Value)
	end;

	CFrame = function(Value)
		return "C_" .. tostring(Value)
	end;

	UDim2 = function(Value)
		return "U_" .. tostring(Value)
	end;

	BrickColor = function(Value)
		return "B_" .. tostring(Value)
	end;

	Color3 = function(Value)
		return "H_" .. tostring(Value)
	end;
}

local function HashValue(Value, Type, IdGenerator)
	if MDEnum[Type] then
		return "E_" .. tostring(Value)
	elseif Type == "Object" then
		local Id = IdGenerator(Value)
		if Id then
			return "I_" .. Id
		else
			return "<<NIL>>"
		end
	else
		local Function = HashValueLookup[Type]
		assert(Function, "Bad type: " .. Type)
		return Function(Value)
	end
end

local function ValueListSort(A, B)
	return #A.ObjectList > #B.ObjectList
end

function BitEncodeInstance.Write(Buffer, Model)
	CachedMDClass = {}
	local Descendants = Model:GetDescendants()
	local Length = #Descendants
	local InstancesToIgnore = {}

	do
		local Index = 1
		while Index <= Length do
			local Descendant = Descendants[Index]
			print(Descendant.ClassName)
			if MDClass[Descendant.ClassName].Creatable then
				Index = Index + 1
			else
				Descendants[Index] = Descendants[Length]
				Descendants[Length] = nil
				Length = Length - 1
				InstancesToIgnore[Descendant] = true
			end
		end
	end

	local InstanceIdGenerator = 1
	local InstanceToId = {}
	local function GenerateId(Object)
		if Object and Object:IsDescendantOf(Model) then
			local Id = InstanceToId[Object]
			if not Id then
				Id = InstanceIdGenerator
				InstanceIdGenerator = InstanceIdGenerator + 1
				InstanceToId[Object] = Id
			end

			return Id
		else
			return 0
		end
	end

	local AllPropertyValueBucket = {}
	local function AddValue(Object, Property, Value)
		if Value == nil then
			assert(Property.Type == "Object", "Nil Value for non-Instance type `" .. Property.Type .. "`")
		end

		local PropertyData = AllPropertyValueBucket[Property.NSName]
		if not PropertyData then
			PropertyData = {
				Property = Property;
				ValueMap = {};
				InstanceCount = 0;
			}

			AllPropertyValueBucket[Property.NSName] = PropertyData
		end

		PropertyData.InstanceCount = PropertyData.InstanceCount + 1

		local HashedName = HashValue(Value, Property.Type, GenerateId)
		local ValueInfo = PropertyData.ValueMap[HashedName]
		if ValueInfo then
			ValueInfo.ObjectList[#ValueInfo.ObjectList + 1] = Object
		else
			PropertyData.ValueMap[HashedName] = {ObjectList = {Object}, Value = Value, Property = Property}
		end
	end

	local UsedClassSet = {}
	for _, Descendant in ipairs(Descendants) do
		local ClassThing = MDClass[Descendant.ClassName]
		UsedClassSet[ClassThing] = true

		for _, Property in ipairs(GetPropertyList(Descendant.ClassName)) do
			AddValue(Descendant, Property, Descendant[Property.Name])
		end
	end

	local InstanceRefWidth = math.ceil(math.log(InstanceIdGenerator + 1) / 0.69314718055995)

	local function GetSize(Value, Type)
		if Type == "string" then
			return 8 * #Value
		else
			local Enumeration = MDEnum[Type]
			if Enumeration then
				return Enumeration.BitWidth
			elseif Type == "string" then
				return -1
			elseif Type == "int" then
				return 32
			elseif Type == "float" then
				return 32
			elseif Type == "double" then
				return 64
			elseif Type == "bool" then
				return 1
			elseif Type == "Vector3" then
				return 96
			elseif Type == "Vector2" then
				return 64
			elseif Type == "CFrame" then
				return 192
			elseif Type == "UDim2" then
				return 128
			elseif Type == "BrickColor" then
				return 6
			elseif Type == "Color3" then
				return 96
			elseif Type == "Object" then
				return InstanceRefWidth
			else
				error("Bad type to TypeWidth: `" .. Type .. "`", 2)
			end
		end
	end

	local function WriteValue(BitBuffer, Type, Value)
		local Enumeration = MDEnum[Type]
		if Enumeration then
			BitBuffer:WriteUnsigned(Enumeration.BitWidth, Enumeration.ValueToId[Value])
		elseif Type == "string" then
			BitBuffer:WriteString(Value)
		elseif Type == "int" then
			BitBuffer:WriteSigned(32, Value)
		elseif Type == "float" then
			BitBuffer:WriteFloat32(Value)
		elseif Type == "double" then
			BitBuffer:WriteFloat64(Value)
		elseif Type == "bool" then
			BitBuffer:WriteBool(Value)
		elseif Type == "Vector3" then
			BitBuffer:WriteFloat32(Value.X)
			BitBuffer:WriteFloat32(Value.Y)
			BitBuffer:WriteFloat32(Value.Z)
		elseif Type == "CFrame" then
			local Position = Value.Position
			BitBuffer:WriteFloat32(Position.X)
			BitBuffer:WriteFloat32(Position.Y)
			BitBuffer:WriteFloat32(Position.Z)
			BitBuffer:WriteRotation(Value)
		elseif Type == "BrickColor" then
			BitBuffer:WriteBrickColor(Value)
		elseif Type == "Color3" then
			BitBuffer:WriteFloat32(Value.R)
			BitBuffer:WriteFloat32(Value.G)
			BitBuffer:WriteFloat32(Value.B)
		elseif Type == "Vector2" then
			BitBuffer:WriteFloat32(Value.X)
			BitBuffer:WriteFloat32(Value.Y)
		elseif Type == "UDim2" then
			BitBuffer:WriteSigned(17, Value.X.Offset)
			BitBuffer:WriteFloat32(Value.X.Scale)
			BitBuffer:WriteSigned(17, Value.Y.Offset)
			BitBuffer:WriteFloat32(Value.Y.Scale)
		elseif Type == "Object" then
			if Value then
				BitBuffer:WriteUnsigned(InstanceRefWidth, InstanceToId[Value])
			else
				BitBuffer:WriteUnsigned(InstanceRefWidth, 0)
			end
		end
	end

	local UsedClassList = {}
	local UsedClassListLength = 0
	local ClassNameToId = {}
	local ListedClassSet = {}

	for Class in next, UsedClassSet do
		repeat
			UsedClassListLength = UsedClassListLength + 1
			UsedClassList[UsedClassListLength] = Class
			ListedClassSet[Class] = true
			ClassNameToId[Class.ClassName] = UsedClassListLength - 1
			Class = MDClass[Class.BaseClassName]
			if ListedClassSet[Class] then
				break
			end
		until not Class
	end

	local MyClassIdWidth = math.ceil(math.log(UsedClassListLength + 1) / 0.69314718055995)
	Buffer:WriteUnsigned(ClassIdWidthWidth, MyClassIdWidth)
	Buffer:WriteUnsigned(5, InstanceRefWidth)
	Buffer:WriteUnsigned(MyClassIdWidth, UsedClassListLength)

	for _, Class in ipairs(UsedClassList) do
		Buffer:WriteUnsigned(ClassIdWidth, Class.Id)
		for _, Property in ipairs(GetPropertyList(Class.ClassName)) do
			if Property.Class.ClassName == Class.ClassName then
				local ModelPropertyData = AllPropertyValueBucket[Property.NSName]
				local ValueList = {}
				local ValueListLength = 0

				for _, Value in next, ModelPropertyData.ValueMap do
					ValueListLength = ValueListLength + 1
					ValueList[ValueListLength] = Value
				end

				table.sort(ValueList, ValueListSort)

				local AtlasedValueCount = 0
				for _, Value in ipairs(ValueList) do
					local ValueSize = GetSize(Value.Value, Value.Property.Type)
					local ValueCount = #Value.ObjectList
					local SavedMemory = ValueCount * ValueSize
					local ExtraMemory = 1 + ValueSize + (AtlasedValueCount + 2) * ValueSize

					if SavedMemory > ExtraMemory then
						AtlasedValueCount = AtlasedValueCount + 1
						Value.Atlased = true
						Value.AtlasId = AtlasedValueCount
					end
				end

				assert(ValueListLength > 0, "Value list should have at least one value, since property is present")
				if ValueListLength == 1 then
					Property.Mode = "Single"
					Buffer:WriteBool(false)
					if Property.NSName == "BasePart::Rotation" then
						Buffer:WriteRotation(ValueList[1].ObjectList[1].CFrame)
					else
						WriteValue(Buffer, Property.Type, ValueList[1].Value)
					end
				else
					Property.Mode = "Atlas"
					Buffer:WriteBool(true)
					for Index = 1, AtlasedValueCount do
						local Value = ValueList[Index]
						Buffer:WriteBool(true)
						if Property.NSName == "BasePart::Rotation" then
							Buffer:WriteRotation(Value.ObjectList[1].CFrame)
						else
							WriteValue(Buffer, Value.Property.Type, Value.Value)
						end
					end

					Buffer:WriteBool(false)
				end
			end
		end
	end

	Buffer:WriteUnsigned(MyClassIdWidth, ClassNameToId[Model.ClassName])
	if InstanceToId[Model] then
		Buffer:WriteBool(true)
		Buffer:WriteUnsigned(InstanceRefWidth, InstanceToId[Model])
	else
		Buffer:WriteBool(false)
	end

	for _, Property in ipairs(GetPropertyList(Model.ClassName)) do
		if Property.Mode == "Atlas" then
			local ModelPropData = AllPropertyValueBucket[Property.NSName]
			local ValueInfo = ModelPropData.ValueMap[HashValue(Model[Property.Name], Property.Type, GenerateId)]
			if ValueInfo.Atlased then
				for _ = 1, ValueInfo.AtlasId do
					Buffer:WriteBool(true)
				end

				Buffer:WriteBool(false)
			else
				Buffer:WriteBool(false)
				if Property.NSName == "BasePart::Rotation" then
					Buffer:WriteRotation(Model.CFrame)
				else
					WriteValue(Buffer, ValueInfo.Property.Type, ValueInfo.Value)
				end
			end
		--elseif Property.Mode == "Single" then
		else
			error("unreachable, bad prop mode: " .. tostring(Property.Mode) .. " on prop " .. Property.NSName .. " (" .. tostring(Property) .. ")", 2)
		end
	end

	for _, Descendant in ipairs(Model:GetDescendants()) do
		if not InstancesToIgnore[Descendant] then
			Buffer:WriteBool(true)
		end
	end

	Buffer:WriteBool(false)
end

function BitEncodeInstance.Read(Buffer)
	CachedMDClass = {}

	local MyClassIdWidth = Buffer:ReadUnsigned(ClassIdWidthWidth)
	local InstanceRefWidth = Buffer:ReadUnsigned(5)
	local UsedClassCount = Buffer:ReadUnsigned(MyClassIdWidth)

	local function ReadValue(BitBuffer, Type)
		local Enumeration = MDEnum[Type]
		if Enumeration then
			return Enumeration.ValueArray[BitBuffer:ReadUnsigned(Enumeration.BitWidth) + 1]
		elseif Type == "string" then
			return BitBuffer:ReadString()
		elseif Type == "int" then
			return BitBuffer:ReadSigned(32)
		elseif Type == "float" then
			return BitBuffer:ReadFloat32()
		elseif Type == "double" then
			return BitBuffer:ReadFloat64()
		elseif Type == "bool" then
			return BitBuffer:ReadBool()
		elseif Type == "Vector3" then
			local X = BitBuffer:ReadFloat32()
			local Y = BitBuffer:ReadFloat32()
			local Z = BitBuffer:ReadFloat32()
			return Vector3.new(X, Y, Z)
		elseif Type == "CFrame" then
			local X = BitBuffer:ReadFloat32()
			local Y = BitBuffer:ReadFloat32()
			local Z = BitBuffer:ReadFloat32()
			local Rotation = BitBuffer:ReadRotation()
			return CFrame.new(X, Y, Z) * Rotation
		elseif Type == "BrickColor" then
			return BitBuffer:ReadBrickColor()
		elseif Type == "Color3" then
			local R = BitBuffer:ReadFloat32()
			local G = BitBuffer:ReadFloat32()
			local B = BitBuffer:ReadFloat32()
			return Color3.new(R, G, B)
		elseif Type == "Vector2" then
			local X = BitBuffer:ReadFloat32()
			local Y = BitBuffer:ReadFloat32()
			return Vector2.new(X, Y)
		elseif Type == "UDim2" then
			local XO = BitBuffer:ReadSigned(17)
			local XS = BitBuffer:ReadFloat32()
			local YO = BitBuffer:ReadSigned(17)
			local YS = BitBuffer:ReadFloat32()
			return UDim2.new(XS, XO, YS, YO)
		elseif Type == "Object" then
			local Value = BitBuffer:ReadUnsigned(InstanceRefWidth)
			if Value == 0 then
				return nil
			else
				return Value
			end
		end
	end

	local UsedClassList = {}
	local UsedClassListLength = 0
	for _ = 1, UsedClassCount do
		local ClassId = Buffer:ReadUnsigned(ClassIdWidth)
		local Class = IdToClass[ClassId]
		UsedClassListLength = UsedClassListLength + 1
		UsedClassList[UsedClassListLength] = Class

		for _, Property in ipairs(GetPropertyList(Class.ClassName)) do
			if Property.Class.ClassName == Class.ClassName then
				if Buffer:ReadBool() then
					Property.Mode = "Atlas"
					Property.ValueAtlas = {}
					local AtlasId = 1

					while Buffer:ReadBool() do
						if Property.NSName == "BasePart::Rotation" then
							Property.ValueAtlas[AtlasId] = Buffer:ReadRotation()
						else
							Property.ValueAtlas[AtlasId] = ReadValue(Buffer, Property.Type)
						end

						AtlasId = AtlasId + 1
					end
				else
					Property.Mode = "Single"
					if Property.NSName == "BasePart::Rotation" then
						Property.Value = Buffer:ReadRotation()
					else
						Property.Value = ReadValue(Buffer, Property.Type)
					end
				end
			end
		end
	end

	local InstanceIdToInstance = {}
	local InstanceRefsToPatch = {}
	local InstanceRefsToPatchLength = 0

	local function ReadObject(BitBuffer)
		local ClassId = BitBuffer:ReadUnsigned(MyClassIdWidth)
		local Class = UsedClassList[ClassId + 1]
		local Object

		if not Class or Class.ClassName == "BevelMesh" or Class.ClassName == "Instance" or Class.ClassName == "FaceInstance" then
			Object = Instance.new("CylinderMesh")
		elseif Class.ClassName == "BasePart" or Class.ClassName == "PVInstance" then
			Object = Instance.new("Part")
		else
			Object = Instance.new(Class.ClassName)
		end

		if BitBuffer:ReadBool() then
			InstanceIdToInstance[BitBuffer:ReadUnsigned(InstanceRefWidth)] = Object
		end

		local DeferredProperties = {}
		local DeferredPropertiesLength = 0

		for _, Property in ipairs(GetPropertyList(Object.ClassName)) do
			if Property.Mode == "Atlas" then
				local AtlasId = 0
				while BitBuffer:ReadBool() do
					AtlasId = AtlasId + 1
				end

				local Value
				if AtlasId == 0 then
					if Property.NSName == "BasePart::Rotation" then
						Value = BitBuffer:ReadRotation()
					else
						Value = ReadValue(BitBuffer, Property.Type)
					end
				else
					Value = Property.ValueAtlas[AtlasId]
				end

				if Property.Type == "Object" then
					InstanceRefsToPatchLength = InstanceRefsToPatchLength + 1
					InstanceRefsToPatch[InstanceRefsToPatchLength] = {
						Object = Object;
						Property = Property.Name;
						Value = Value;
					}
				elseif Property.NSName == "BasePart::Rotation" then
					Object.CFrame = CFrame.new(Object.Position) * Value
				elseif Property.NSName == "BasePart::Size" then
					DeferredPropertiesLength = DeferredPropertiesLength + 1
					DeferredProperties[DeferredPropertiesLength] = {
						Property = Property.Name;
						Value = Value;
					}
				else
					pcall(function()
						Object[Property.Name] = Value
					end)
				end
			elseif Property.Mode == "Single" then
				if Property.Type == "Object" then
					InstanceRefsToPatchLength = InstanceRefsToPatchLength + 1
					InstanceRefsToPatch[InstanceRefsToPatchLength] = {
						Object = Object;
						Property = Property.Name;
						Value = Property.Value;
					}
				elseif Property.NSName == "BasePart::Rotation" then
					Object.CFrame = CFrame.new(Object.Position) * Property.Value
				else
					Object[Property.Name] = Property.Value
				end
			else
				error("unreachable, bad prop mode: " .. tostring(Property.Mode) .. " on property " .. Property.NSName .. " (" .. tostring(Property) .. ")", 2)
			end
		end

		for _, Property in ipairs(DeferredProperties) do
			Object[Property.Property] = Property.Value
		end

		while BitBuffer:ReadBool() do
			local Child = ReadObject(BitBuffer)
			Child.Parent = Object
		end

		return Object
	end

	local Root = ReadObject(Buffer)
	for _, PatchRef in ipairs(InstanceRefsToPatch) do
		PatchRef.Object[PatchRef.Property] = InstanceIdToInstance[PatchRef.Value]
	end

	return Root
end

return BitEncodeInstance