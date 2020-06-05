/++
+/
module mir.bignum.big_int;

import std.traits;
import mir.bitop;
import mir.utility;

/++
Stack-allocated big signed integer.
+/
struct BigInt(size_t maxSize64)
    if (maxSize64 && maxSize64 <= ushort.max)
{
    import mir.bignum.low_level_view;
    import mir.bignum.fixed_int;

    ///
    bool sign;
    ///
    uint length;
    ///
    size_t[ulong.sizeof / size_t.sizeof * maxSize64] data = void;

    @disable this(this);

    ///
    BigInt copy() @property
    {
        return BigInt(sign, length, data);
    }

    ///
    bool opEquals(ref const BigInt rhs)
        const @safe pure nothrow @nogc
    {
        return view == rhs.view;
    }

    /++
    +/
    auto opCmp(ref const BigInt rhs) 
        const @safe pure nothrow @nogc
    {
        return view.opCmp(rhs.view);
    }

    ///
    BigIntView!size_t view()() @property
    {
        version (LittleEndian)
            return typeof(return)(data[0 .. length], sign);
        else
            return typeof(return)(data[$ - length .. $], sign);
    }

    ///
    BigIntView!(const size_t) view()() const @property
    {
        version (LittleEndian)
            return typeof(return)(data[0 .. length], sign);
        else
            return typeof(return)(data[$ - length .. $], sign);
    }

    ///
    void normalize()()
    {
        auto norm = view.normalized;
        this.length = cast(uint) norm.unsigned.coefficients.length;
        this.sign = norm.sign;
    }

    /++
    +/
    void putCoefficient(size_t value)
    {
        assert(length < data.length);
        version (LittleEndian)
            data[length++] = value;
        else
            data[$ - ++length] = value;
    }

    /++
    Performs `size_t overflow = big *= scalar` operatrion.
    Precondition: non-empty coefficients
    Params:
        rhs = unsigned value to multiply by
    Returns:
        unsigned overflow value
    +/
    size_t opOpAssign(string op : "*")(size_t rhs, size_t overflow = 0u)
        @safe pure nothrow @nogc
    {
        overflow = view.unsigned.opOpAssign!op(rhs, overflow);
        if (overflow && length < data.length)
        {
            putCoefficient(overflow);
            overflow = 0;
        }
        return overflow;
    }

    /++
    Performs `size_t overflow = big *= fixed` operatrion.
    Precondition: non-empty coefficients
    Params:
        rhs = unsigned value to multiply by
    Returns:
        unsigned overflow value
    +/
    UInt!size opOpAssign(string op : "*", size_t size)(UInt!size rhs, UInt!size overflow = 0)
        @safe pure nothrow @nogc
    {
        return length ? view.unsigned.opOpAssign!("*")(rhs, overflow) : overflow;
    }

    /++
    Performs `size_t overflow = big *= fixed` operatrion.
    Precondition: non-empty coefficients
    Params:
        rhs = unsigned value to multiply by
    Returns:
        overflow
    +/
    bool opOpAssign(string op)(ref const BigInt rhs)
        @safe pure nothrow @nogc
        if (op == "+" || op == "-")
    {
        sizediff_t diff = length - rhs.length;
        if (diff < 0)
        {
            view.unsigned.leastSignificantFirst[length .. rhs.length] = 0;
            length = rhs.length;
        }
        else
        if (length == 0)
            return false;
        auto thisView = view;
        auto overflow = thisView.opOpAssign!op(rhs.view);
        this.sign = thisView.sign;
        if (overflow)
        {
            if (length < data.length)
            {
                putCoefficient(overflow);
                overflow = false;
            }
        }
        else
        {
            normalize;
        }
        return overflow;
    }

    /++
    +/
    static BigInt fromHexString()(scope const(char)[] str)
        @trusted pure
    {
        BigInt ret;
        auto len = str.length / (size_t.sizeof * 2) + (str.length % (size_t.sizeof * 2) != 0);
        if (len > ret.data.length)
        {
            version(D_Exceptions)
                throw hexStringException;
            else
                assert(0, hexStringErrorMsg);
        }
        ret.length = cast(uint)len;
        ret.view.unsigned.fromHexStringImpl(str);
        return ret;
    }

    ///
    bool mulPow5(size_t degree)
    {
        // assert(approxCanMulPow5(degree));
        assert(length);
        enum n = MaxWordPow5!size_t;
        enum wordInit = size_t(5) ^^ n;
        size_t word = wordInit;
        bool of;
        while(degree)
        {
            if (degree >= n)
            {
                degree -= n;
            }
            else
            {
                word = 1;
                do word *= 5;
                while(--degree);
            }
            if (auto overflow = view *= word)
            {
                of = length >= data.length;
                if (!of)
                    putCoefficient(overflow);
            }
        }
        return of;
    }

    ///
    ref BigInt opOpAssign(string op)(size_t shift)
        @safe pure nothrow @nogc return
        if (op == "<<" || op == ">>")
    {
        auto index = shift / (size_t.sizeof * 8);
        auto bs = shift % (size_t.sizeof * 8);
        auto ss = size_t.sizeof * 8 - bs;
        static if (op == ">>")
        {
            if (index >= length)
            {
                length = 0;
                return this;
            }
            auto d = view.leastSignificantFirst;
            if (bs)
            {
                foreach (j; 0 .. d.length - (index + 1))
                {
                    d[j] = (d[j + index] >>> bs) | (d[j + (index + 1)] << ss);
                }
            }
            else
            {
                foreach (j; 0 .. d.length - (index + 1))
                {
                    d[j] = d[j + index];
                }
            }
            auto most = d[$ - (index + 1)] = d.back >>> bs;
            length -= index + (most == 0);
        }
        else
        {
            if (index >= data.length)
            {
                length = 0;
                return this;
            }

            if (bs)
            {
                auto most = view.unsigned.mostSignificant >> ss;
                length += index;
                if (length < data.length)
                {
                    if (most)
                    {
                        length++;
                        view.unsigned.mostSignificant = most;
                        length--;
                    }
                }
                else
                {
                    length = data.length;
                }

                auto d = view.leastSignificantFirst;
                foreach_reverse (j; index + 1 .. length)
                {
                    d[j] = (d[j - index] << bs) | (d[j - (index + 1)] >> ss);
                }
                d[index] = d.front << bs;
            }
            else
            {
                length = cast(uint) min(length + index, cast(uint)data.length);
                auto d = view.leastSignificantFirst;
                foreach_reverse (j; index .. length)
                {
                    d[j] = d[j - index];
                }
            }
            view.leastSignificantFirst[0 .. index] = 0;
        }
        return this;
    }
}

///
unittest
{
    auto a = BigInt!4.fromHexString("4b313b23aa560e1b0985f89cbe6df5460860e39a64ba92b4abdd3ee77e4e05b8");
    auto b = BigInt!4.fromHexString("c39b18a9f06fd8e962d99935cea0707f79a222050aaeaaaed17feb7aa76999d7");
    auto c = BigInt!4.fromHexString("7869dd864619cace5953a09910327b3971413e6aa5f417fa25a2ac93291b941f");
    c.sign = true;
    assert(a != b);
    assert(a < b);
    a -= b;
    assert(a.sign);
    assert(a == c);
    a -= a;
    assert(!a.sign);
    assert(!a.length);

    auto d = BigInt!4.fromHexString("0de1a911c6dc8f90a7169a148e65d22cf34f6a8254ae26362b064f26ac44218a");
    assert((b *= 0x7869dd86) == 0x5c019770);
    assert(b == d);

    import mir.bignum.fixed_int;
    d = BigInt!4.fromHexString("856eeb23e68cc73f2a517448862cdc97e83f9dfa23768296724bf00fda7df32a");
    auto o = b *= UInt!128.fromHexString("f79a222050aaeaaa417fa25a2ac93291");
    assert(o == UInt!128.fromHexString("d6d15b99499b73e68c3331eb0f7bf16"));
    assert(b == d);

    d = BigInt!4.fromHexString("d"); // initial value
    d.mulPow5(60);
    c = BigInt!4.fromHexString("81704fcef32d3bd8117effd5c4389285b05d");
    assert(d == c);

    d >>= 80;
    c = BigInt!4.fromHexString("81704fcef32d3bd8");
    assert(d == c);

    c = BigInt!4.fromHexString("c39b18a9f06fd8e962d99935cea0707f79a222050aaeaaaed17feb7aa76999d7");
    d = BigInt!4.fromHexString("9935cea0707f79a222050aaeaaaed17feb7aa76999d700000000000000000000");
    c <<= 80;
    assert(d == c);
    c >>= 80;
    c <<= 84;
    d <<= 4;
    assert(d == c);
}