/*	OOTCPStreamDecoderFormat.hpp
	The formatter behind OOALStringCreateWithFormatAndArguments() (OOTCPStreamDecoderAbstractionLayer
	.mm), moved into a header of its own (bead oo-0mxm) so the unit tier can test it: plain C++20,
	no Foundation, no oofnd.

	It is -[NSString initWithFormat:arguments:] for the conversions OOTCPStreamDecoder.c uses:
	%u (unsigned), %zu (size_t), %@ (an object handle, written as describe(handle) gives it) and
	%%; a lone '%' at the end is kept. Anything else is copied as it stands (the decoder uses
	nothing else). tests/unit/oofnd/test_tcp_stream_format.cpp pins it against texts GNUstep
	1.31.1 printed for the decoder's own formats.
*/

#ifndef OOTCPSTREAMDECODERFORMAT_HPP
#define OOTCPSTREAMDECODERFORMAT_HPP

// (In game code this is included after oofnd/StdLib.hpp, which has already parsed these.)
#include <cstdarg>
#include <cstddef>
#include <string>
#include <string_view>

namespace OOTCPStreamDecoderFormat {

// Handle is the type the caller passes for %@; describe(handle) is what "%@" prints for it.
template <class Handle, class Describe>
std::string FormatWithArguments(std::string_view format, va_list args, Describe describe)
{
	std::string out;
	for (std::size_t i = 0; i < format.size(); ++i)
	{
		const char c = format[i];
		if (c != '%' || i + 1 == format.size())
		{
			out += c;
			continue;
		}
		const char next = format[i + 1];
		if (next == '%')
		{
			out += '%';
			++i;
		}
		else if (next == 'u')
		{
			out += std::to_string(va_arg(args, unsigned));
			++i;
		}
		else if (next == 'z' && i + 2 < format.size() && format[i + 2] == 'u')
		{
			out += std::to_string(va_arg(args, size_t));
			i += 2;
		}
		else if (next == '@')
		{
			out += describe(va_arg(args, Handle));
			++i;
		}
		else
		{
			out += c;
		}
	}
	return out;
}

}	// namespace OOTCPStreamDecoderFormat

#endif	// OOTCPSTREAMDECODERFORMAT_HPP
