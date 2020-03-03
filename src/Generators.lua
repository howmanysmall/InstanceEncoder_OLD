local DumpParser = require(script.Parent.DumpParser)
local Generators = {}

local ipairs = ipairs

local function GetPropertyDictionary(ClassName)
	local PropertiesRaw = DumpParser:GetPropertiesRaw(ClassName)
	local Properties = {}

	for _, Property in ipairs(PropertiesRaw) do
		Properties[Property.Name] = true
	end

	return Properties
end

local function BuildForEncoding(ClassName)
	local ClassTable = DumpParser:BuildClass(ClassName)
	local SafeProperties = GetPropertyDictionary(ClassName)

	local EncodeTable = {
		Creatable = true;
		BaseClassName = ClassTable.Superclass;
		ClassName = ClassName;
	}

	local PropertyMap = {}

	for _, Member in ipairs(ClassTable.Members) do
		if Member.MemberType == "Property" and SafeProperties[Member.Name] then
			PropertyMap[Member.Name] = {
				Readonly = false;
				PropertyName = Member.Name;
				PropertyType = string.gsub(Member.ValueType.Name, "Instance", "Object");
			}
		end
	end

	EncodeTable.PropertyMap = PropertyMap
	return EncodeTable
end

function Generators.GenerateMDClass()
	local Dump = DumpParser:GetDump()
	local MDClass = {}

	for _, Class in ipairs(Dump.Classes) do
		MDClass[Class.Name] = BuildForEncoding(Class.Name)
	end

	return MDClass
end

function Generators.GenerateMDEnum()
	local Dump = DumpParser:GetDump()
	local MDEnum = {}

	for _, Enumeration in ipairs(Dump.Enums) do
		local ValueMap = {}

		for _, Value in ipairs(Enumeration.Items) do
			ValueMap[Value.Name] = true
		end

		MDEnum[Enumeration.Name] = {
			EnumName = Enumeration.Name;
			ValueMap = ValueMap;
		}
	end

	return MDEnum
end

return Generators