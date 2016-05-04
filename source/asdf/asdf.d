/++
ASDF Representation

Copyright: Tamedia Digital, 2016

Authors: Ilya Yaroshenko

License: MIT

Macros:
SUBMODULE = $(LINK2 asdf_$1.html, asdf.$1)
SUBREF = $(LINK2 asdf_$1.html#.$2, $(TT $2))$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
T4=$(TR $(TDNW $(LREF $1)) $(TD $2) $(TD $3) $(TD $4))
+/
module asdf.asdf;

import std.exception;
import std.range.primitives;
import std.typecons;

version(X86)
	version = X86_Any;

version(X86_64)
	version = X86_Any;

///
class AsdfException: Exception
{
	///
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @nogc @safe 
	{
		super(msg, file, line, next);
	}
}

/++
The structure for ASDF manipulation.
+/
struct Asdf
{
	/++
	Plain ASDF data.
	+/
	ubyte[] data;

	/// Creates ASDF using already allocated data
	this(ubyte[] data)
	{
		this.data = data;
	}

	/// Creates ASDF from a string
	this(in char[] str)
	{
		data = new ubyte[str.length + 5];
		data[0] = 0x05;
		length4 = str.length;
		data[5 .. $] = cast(const(ubyte)[])str;
	}

	///
	unittest
	{
		assert(Asdf("string") == "string");
		assert(Asdf("string") != "String");
	}

	///
	void toString(Dg)(scope Dg sink)
	{
		enforce!AsdfException(data.length);
		auto t = data[0];
		switch(t)
		{
			case 0x00:
				enforce!AsdfException(data.length == 1);
				sink("null");
				break;
			case 0x01:
				enforce!AsdfException(data.length == 1);
				sink("true");
				break;
			case 0x02:
				enforce!AsdfException(data.length == 1);
				sink("false");
				break;
			case 0x03:
				enforce!AsdfException(data.length > 1);
				size_t length = data[1];
				enforce!AsdfException(data.length == length + 2);
				sink(cast(string) data[2 .. $]);
				break;
			case 0x05:
				enforce!AsdfException(data.length == length4 + 5);
				sink("\"");
				sink(cast(string) data[5 .. $]);
				sink("\"");
				break;
			case 0x09:
				auto elems = byElement;
				if(byElement.empty)
				{
					sink("[]");
					break;
				}
				sink("[");
				elems.front.toString(sink);
				elems.popFront;
				foreach(e; elems)
				{
					sink(",");
					e.toString(sink);
				}
				sink("]");
				break;
			case 0x0A:
				auto pairs = byKeyValue;
				if(byKeyValue.empty)
				{
					sink("{}");
					break;
				}
				sink("{\"");
				sink(pairs.front.key);
				sink("\":");
				pairs.front.value.toString(sink);
				pairs.popFront;
				foreach(e; pairs)
				{
					sink(",\"");
					sink(e.key);
					sink("\":");
					e.value.toString(sink);
				}
				sink("}");
				break;
			default:
				enforce!AsdfException(0);
		}
	}

	///
	unittest
	{
		import std.conv: to;
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData.to!string == text);
	}

	/++
	`==` operator overloads for `null`
	+/
	bool opEquals(in Asdf rhs) const
	{
		return data == rhs.data;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`null`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData == asdfData);
	}

	/++
	`==` operator overloads for `null`
	+/
	bool opEquals(typeof(null)) const
	{
		return data.length == 1 && data[0] == 0;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`null`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData == null);
	}

	/++
	`==` operator overloads for `bool`
	+/
	bool opEquals(bool boolean) const
	{
		return data.length == 1 && (data[0] == 0x01 && boolean || data[0] == 0x02 && !boolean);
	}

	///
	unittest
	{
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`true`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData == true);
		assert(asdfData != false);
	}

	/++
	`==` operator overloads for `string`
	+/
	bool opEquals(in char[] str) const
	{
		return data.length >= 5 && data[0] == 0x05 && data[5 .. 5 + length4] == cast(const(ubyte)[]) str;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`"str"`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData == "str");
		assert(asdfData != "stR");
	}

	/++
	Returns:
		input range composed of elements of an array.
	+/
	auto byElement()
	{
		static struct Range
		{
			private ubyte[] _data;
			private Asdf _front;

			void popFront()
			{
				while(!_data.empty)
				{
					uint c = cast(ubyte) _data.front;
					switch(c)
					{
						case 0x00:
						case 0x01:
						case 0x02:
							_front = Asdf(_data[0 .. 1]);
							_data.popFront;
							return;
						case 0x03:
							enforce!AsdfException(_data.length >= 2);
							size_t len = _data[1] + 2;
							enforce!AsdfException(_data.length >= len);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x05:
						case 0x09:
						case 0x0A:
							enforce!AsdfException(_data.length >= 5);
							size_t len = Asdf(_data).length4 + 5;
							enforce!AsdfException(_data.length >= len);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80:
						case 0x81:
						case 0x82:
							_data.popFront;
							continue;
						case 0x83:
							enforce!AsdfException(_data.length >= 2);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x85:
						case 0x89:
						case 0x8A:
							enforce!AsdfException(_data.length >= 5);
							size_t len = Asdf(_data).length4 + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforce!AsdfException(0);
					}
				}
				_front = Asdf.init;
			}

			auto front() @property
			{
				assert(!empty);
				return _front;
			}

			bool empty() @property
			{
				return _front.data.length == 0;
			}
		}
		if(data.empty || data[0] != 0x09)
			return Range.init;
		enforce!AsdfException(length4 == data.length - 5);
		auto ret = Range(data[5 .. $]);
		if(ret._data.length)
			ret.popFront;
		return ret;
	}

	/++
	Returns:
		Input range composed of key-value pairs of an object.
		Elements are type of `Tuple!(const(char)[], "key", Asdf, "value")`.
	+/
	auto byKeyValue()
	{
		static struct Range
		{
			private ubyte[] _data;
			private Tuple!(const(char)[], "key", Asdf, "value") _front;

			void popFront()
			{
				while(!_data.empty)
				{
					enforce!AsdfException(_data.length > 1);
					size_t l = cast(ubyte) _data[0];
					_data.popFront;
					enforce!AsdfException(_data.length >= l);
					_front.key = cast(const(char)[])_data[0 .. l];
					_data.popFrontExactly(l);
					uint c = cast(ubyte) _data.front;
					switch(c)
					{
						case 0x00:
						case 0x01:
						case 0x02:
							_front.value = Asdf(_data[0 .. 1]);
							_data.popFront;
							return;
						case 0x03:
							enforce!AsdfException(_data.length >= 2);
							size_t len = _data[1] + 2;
							enforce!AsdfException(_data.length >= len);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x05:
						case 0x09:
						case 0x0A:
							enforce!AsdfException(_data.length >= 5);
							size_t len = Asdf(_data).length4 + 5;
							enforce!AsdfException(_data.length >= len);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80:
						case 0x81:
						case 0x82:
							_data.popFront;
							continue;
						case 0x83:
							enforce!AsdfException(_data.length >= 2);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x85:
						case 0x89:
						case 0x8A:
							enforce!AsdfException(_data.length >= 5);
							size_t len = Asdf(_data).length4 + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforce!AsdfException(0);
					}
				}
				_front = _front.init;
			}

			auto front() @property
			{
				assert(!empty);
				return _front;
			}

			bool empty() @property
			{
				return _front.value.data.length == 0;
			}
		}
		if(data.empty || data[0] != 0x0A)
			return Range.init;
		enforce!AsdfException(length4 == data.length - 5);
		auto ret = Range(data[5 .. $]);
		if(ret._data.length)
			ret.popFront;
		return ret;
	}

	/// returns 1-byte length
	private size_t length1() const @property
	{
		enforce!AsdfException(data.length >= 2);
		return data[1];
	}

	/// returns 4-byte length
	private size_t length4() const @property
	{
		enforce!AsdfException(data.length >= 5);
		version(X86_Any)
			return (cast(uint[1])cast(ubyte[4])data[1 .. 5])[0];
		else
			static assert(0, "not implemented.");
	}

	void length4(size_t len) const @property
	{
		assert(data.length >= 5);
		assert(len <= uint.max);
		version(X86_Any)
			(cast(uint[1])cast(ubyte[4])data[1 .. 5])[0] = cast(uint) len;
		else
			static assert(0, "not implemented.");
	}
}

/++
Searches a value recursively in an ASDF object.

Params:
	asdf = ASDF data
	keys = input range of keys
Returns
	ASDF value if it was found (first win) or ASDF with empty plain data.
+/
Asdf getValue(Range)(Asdf asdf, Range keys)
	if(is(ElementType!Range : const(char)[]))
{
	if(asdf.data.empty)
		return Asdf.init;
	L: foreach(key; keys)
	{
		if(asdf.data[0] != 0x0A)
			return Asdf.init;
		foreach(e; asdf.byKeyValue)
		{
			if(e.key == key)
			{
				asdf = e.value;
				continue L;
			}
		}
		return Asdf.init;
	}
	return asdf;
}

///
unittest
{
	import asdf.jsonparser;
	import std.range: chunks;
	auto text = cast(const ubyte[])`{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`;
	auto asdfData = text.chunks(13).parseJson(32);
	assert(asdfData.getValue(["inner", "a"]) == true);
	assert(asdfData.getValue(["inner", "b"]) == false);
	assert(asdfData.getValue(["inner", "c"]) == "32323");
	assert(asdfData.getValue(["inner", "d"]) == null);
}