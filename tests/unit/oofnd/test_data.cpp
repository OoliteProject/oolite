/*	test_data.cpp
	Unit tests for oofnd/Data.hpp (bead oo-i9q): oo::Data, the replacement for NSData and
	NSMutableData, checked against the NSData behaviour its banner maps (construction, bytes and
	length, appending, zero-filled growth, subranges, equality by content).
*/

#include "oofnd/Data.hpp"

#include "oo_test.hpp"

#include <cstring>
#include <string>
#include <utility>
#include <vector>

OO_TEST(emptyDataHasNoBytesButAValidPointer)
{
	const oo::Data d;
	OO_CHECK(d.empty());
	OO_CHECK_EQ(d.length(), 0u);
	OO_CHECK(d.bytes() != nullptr);
	OO_CHECK(d.span().empty());
	OO_CHECK(d.stringView().empty());
	unsigned char dst[1] = {7};
	std::memcpy(dst, d.bytes(), d.length());
	OO_CHECK_EQ(dst[0], 7);
}

OO_TEST(dataWithBytesCopiesThem)
{
	unsigned char src[] = {1, 2, 3, 0, 255};
	oo::Data d(src, sizeof src);
	src[0] = 9;
	OO_CHECK_EQ(d.length(), 5u);
	OO_CHECK_EQ(d.bytes()[0], 1);
	OO_CHECK_EQ(d.bytes()[3], 0);
	OO_CHECK_EQ(d.bytes()[4], 255);
}

OO_TEST(nullOrZeroLengthBytesMakeEmptyData)
{
	OO_CHECK(oo::Data(nullptr, 0).empty());
	OO_CHECK(oo::Data(nullptr, 12).empty());
	const char c = 'x';
	OO_CHECK(oo::Data(&c, 0).empty());
}

OO_TEST(fromStringIsTheUtf8BytesWithoutTerminator)
{
	const oo::Data d = oo::Data::fromString("caf\xc3\xa9");
	OO_CHECK_EQ(d.length(), 5u);
	OO_CHECK_EQ(d.bytes()[3], 0xc3);
	OO_CHECK_EQ(d.stringView(), std::string_view("caf\xc3\xa9"));
	OO_CHECK_EQ(d.toString(), std::string("caf\xc3\xa9"));
}

OO_TEST(embeddedNulsSurvive)
{
	const std::string s("a\0b", 3);
	const oo::Data d = oo::Data::fromString(s);
	OO_CHECK_EQ(d.length(), 3u);
	OO_CHECK_EQ(d.toString(), s);
}

OO_TEST(appendBytesAndData)
{
	oo::Data d = oo::Data::fromString("ab");
	d.append("cd", 2);
	d.append(oo::Data::fromString("ef"));
	OO_CHECK_EQ(d.toString(), std::string("abcdef"));
	d.append(nullptr, 3);
	OO_CHECK_EQ(d.length(), 6u);
}

OO_TEST(appendingToItselfDoublesTheContents)
{
	oo::Data d = oo::Data::fromString("xyz");
	d.append(d);
	OO_CHECK_EQ(d.toString(), std::string("xyzxyz"));
}

OO_TEST(setLengthGrowsWithZerosAndTruncates)
{
	oo::Data d = oo::Data::fromString("abc");
	d.setLength(5);
	OO_CHECK_EQ(d.length(), 5u);
	OO_CHECK_EQ(d.bytes()[3], 0);
	OO_CHECK_EQ(d.bytes()[4], 0);
	d.setLength(1);
	OO_CHECK_EQ(d.toString(), std::string("a"));
}

OO_TEST(mutableBytesWriteThrough)
{
	oo::Data d = oo::Data::fromString("abc");
	d.mutableBytes()[1] = 'X';
	OO_CHECK_EQ(d.toString(), std::string("aXc"));
	oo::Data empty;
	OO_CHECK(empty.mutableBytes() == nullptr);
}

OO_TEST(subdataIsTheRangeClampedToTheBytes)
{
	const oo::Data d = oo::Data::fromString("0123456789");
	OO_CHECK_EQ(d.subdata(2, 3).toString(), std::string("234"));
	OO_CHECK_EQ(d.subdata(0, 10), d);
	OO_CHECK_EQ(d.subdata(8, 100).toString(), std::string("89"));
	OO_CHECK(d.subdata(10, 1).empty());
	OO_CHECK(d.subdata(50, 1).empty());
	OO_CHECK(d.subdata(3, 0).empty());
}

OO_TEST(equalityIsByContent)
{
	OO_CHECK(oo::Data::fromString("abc") == oo::Data::fromString("abc"));
	OO_CHECK(!(oo::Data::fromString("abc") == oo::Data::fromString("abd")));
	OO_CHECK(!(oo::Data::fromString("abc") == oo::Data::fromString("ab")));
	OO_CHECK(oo::Data() == oo::Data(nullptr, 0));
}

OO_TEST(copiesAreIndependentAndMovesTransfer)
{
	oo::Data a = oo::Data::fromString("abc");
	oo::Data b = a;
	b.mutableBytes()[0] = 'z';
	OO_CHECK_EQ(a.toString(), std::string("abc"));
	OO_CHECK_EQ(b.toString(), std::string("zbc"));

	const std::uint8_t* before = a.bytes();
	oo::Data c = std::move(a);
	OO_CHECK(c.bytes() == before);
	OO_CHECK_EQ(c.toString(), std::string("abc"));
}

OO_TEST(vectorRoundTrip)
{
	std::vector<std::uint8_t> v{4, 5, 6};
	const std::uint8_t* raw = v.data();
	oo::Data d(std::move(v));
	OO_CHECK(d.bytes() == raw);
	OO_CHECK_EQ(d.vector().size(), 3u);
	std::vector<std::uint8_t> out = std::move(d).vector();
	OO_CHECK_EQ(out.size(), 3u);
	OO_CHECK_EQ(out[2], 6);
}

OO_TEST_MAIN()
