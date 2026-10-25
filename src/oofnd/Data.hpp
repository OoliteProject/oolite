/*	oofnd/Data.hpp
	oo::Data: a byte buffer, the C++ shape of NSData / NSMutableData (bead oo-i9q).

	    Foundation                                  oofnd
	    ------------------------------------------  ------------------------------------------------
	    NSData *d / NSMutableData *d                oo::Data d        (a value; see below)
	    [NSData data]                               oo::Data{}
	    [NSData dataWithBytes:p length:n]           oo::Data(p, n)
	    [s dataUsingEncoding:NSUTF8StringEncoding]  oo::Data::fromString(utf8)
	    [d bytes]  /  [d length]                    d.bytes()  /  d.length()
	    [d mutableBytes]                            d.mutableBytes()
	    [d appendBytes:p length:n] / appendData:    d.append(p, n)  /  d.append(other)
	    [d setLength:n]                             d.setLength(n)   (new bytes are zero, as NSData's)
	    [d subdataWithRange:r]                      d.subdata(location, length)   (clamped, see below)
	    [d isEqualToData:e]                         d == e
	    [NSData dataWithContentsOfFile:p]           oo::fs::readFile(p)            (oofnd/FileSystem.hpp)
	    [d writeToFile:p atomically:YES]            oo::fs::writeFile(p, d, oo::fs::WriteMode::atomic)

	SEMANTICS (proposed ADR-0028):

	  * A VALUE type over std::vector<std::uint8_t>, not a RefCounted object. NSData is immutable
	    and shared by retain; in C++ a const Data& or a move gives the same no-copy hand-off
	    without a count, and NSMutableData's "mutate my own copy" is simply a non-const Data.
	    A Data that must be shared by several owners goes in an oo::Ref of an owning class, as any
	    other value does.
	  * subdata() clamps an out-of-range request to the bytes that exist instead of raising
	    NSRangeException: oofnd does not throw (README). Callers that relied on the exception
	    check the range first.
	  * bytes() of an empty Data is never null (it points at a zero-length buffer), so
	    memcpy(dst, d.bytes(), d.length()) is always well-defined; NSData returned NULL there.

	Header-only, C++20, no exceptions thrown by oofnd itself (std::vector may still report
	allocation failure as the standard library does).
*/

#ifndef OOFND_DATA_HPP
#define OOFND_DATA_HPP

// Objective-C++ callers see OOCocoa.h's `#define true 1` / `#define false 0`; C++20 needs the
// keywords (requires-clauses, <=> in the standard headers this pulls in). Suspend the macros for
// this header and restore them at its end (proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace oo {

class Data
{
public:
	Data() = default;

	Data(const void* bytes, std::size_t length)
	{
		append(bytes, length);
	}

	explicit Data(std::vector<std::uint8_t> bytes) noexcept : bytes_(std::move(bytes)) {}

	// The UTF-8 bytes of a string, without a terminator (dataUsingEncoding:NSUTF8StringEncoding).
	static Data fromString(std::string_view utf8)
	{
		return Data(utf8.data(), utf8.size());
	}

	const std::uint8_t* bytes() const noexcept { return bytes_.empty() ? &kEmpty : bytes_.data(); }
	std::uint8_t* mutableBytes() noexcept { return bytes_.data(); }  // null when empty, as NSMutableData's
	std::size_t length() const noexcept { return bytes_.size(); }
	bool empty() const noexcept { return bytes_.empty(); }

	std::span<const std::uint8_t> span() const noexcept { return {bytes(), length()}; }

	// The bytes reinterpreted as characters (no transcoding, no terminator required).
	std::string_view stringView() const noexcept
	{
		return {reinterpret_cast<const char*>(bytes()), length()};
	}

	std::string toString() const { return std::string(stringView()); }

	const std::vector<std::uint8_t>& vector() const& noexcept { return bytes_; }
	std::vector<std::uint8_t> vector() && noexcept { return std::move(bytes_); }

	void append(const void* bytes, std::size_t length)
	{
		if (length == 0 || bytes == nullptr)  return;
		const auto* p = static_cast<const std::uint8_t*>(bytes);
		bytes_.insert(bytes_.end(), p, p + length);
	}

	void append(const Data& other)
	{
		if (&other == this)
		{
			const std::vector<std::uint8_t> copy = bytes_;
			bytes_.insert(bytes_.end(), copy.begin(), copy.end());
			return;
		}
		append(other.bytes_.data(), other.bytes_.size());
	}

	void setLength(std::size_t length) { bytes_.resize(length, 0); }

	// Bytes [location, location + length), clamped to what exists.
	Data subdata(std::size_t location, std::size_t length) const
	{
		if (location >= bytes_.size())  return Data();
		const std::size_t available = bytes_.size() - location;
		if (length > available)  length = available;
		return Data(bytes_.data() + location, length);
	}

	friend bool operator==(const Data& a, const Data& b) noexcept { return a.bytes_ == b.bytes_; }

private:
	static constexpr std::uint8_t kEmpty = 0;

	std::vector<std::uint8_t> bytes_;
};

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_DATA_HPP
