/*	test_plist_writers.cpp
	The old-style and XML writers (bead oo-pig) and oo::parsePropertyList, OOPropertyListFromData's
	dispatcher. Each fixture below is an XML plist and the exact bytes GNUstep 1.31.1 wrote for it:
	OldSchoolPropertyListWriting.m's -oldSchoolPListFormatWithErrorDescription: ("...Old") and
	+[NSPropertyListSerialization dataFromPropertyList:format:NSPropertyListXMLFormat_v1_0 ...]
	("...Xml"), captured with a throwaway harness that parsed the input with NSPropertyListSerialization
	and wrote the result. oofnd parses the same input (its readers are pinned against GNUstep in
	the other test_plist_*.cpp files) and must write the same bytes. "WRITEERR <text>" is the
	harness's record of a nil result and its error description. Fixtures GNUstep cannot produce
	correctly (ADR-0027) are compared in the tests marked ADR0027 instead.
	meson test --suite oofnd-plist
*/

// Included as game code will include it, after OOCocoa.h's true/false macros (see test_plist.cpp).
#define true						1
#define false						0
#include "oofnd/PListParsing.hpp"
#include "oofnd/PListWriting.hpp"
static_assert(std::is_same_v<decltype(true), int>, "the PList headers must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"
#include "plist_dump.hpp"

#include <string>
#include <string_view>

using namespace std::string_view_literals;

namespace {

const std::string_view kW01In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<dict>\n"
	"<key>name</key><string>Cobra Mk III</string>\n"
	"<key>count</key><integer>3</integer>\n"
	"<key>negative</key><integer>-42</integer>\n"
	"<key>big</key><integer>18446744073709551615</integer>\n"
	"<key>ratio</key><real>0.1</real>\n"
	"<key>third</key><real>0.333333333333333314829616256247</real>\n"
	"<key>huge</key><real>1e300</real>\n"
	"<key>whole</key><real>100</real>\n"
	"<key>tiny</key><real>1e-7</real>\n"
	"<key>negzero</key><real>-0.0</real>\n"
	"<key>yes</key><true/>\n"
	"<key>no</key><false/>\n"
	"<key>empty array</key><array/>\n"
	"<key>empty dict</key><dict/>\n"
	"<key>nested</key><array><string>a</string><array><string>b</string><dict><key>c</key><string>d</string></dict></array></array>\n"
	"<key>data0</key><data></data>\n"
	"<key>data1</key><data>AQ==</data>\n"
	"<key>data3</key><data>AQID</data>\n"
	"<key>data4</key><data>AQIDBA==</data>\n"
	"<key>data8</key><data>AQIDBAUGBwg=</data>\n"
	"</dict>\n"
	"</plist>\n"sv;
const std::string_view kW01Old =
	"{\n"
	"\tbig = 9223372036854775807;\n"
	"\tcount = 3;\n"
	"\tdata0 = <>;\n"
	"\tdata1 = <01>;\n"
	"\tdata3 = <010203>;\n"
	"\tdata4 = <01020304>;\n"
	"\tdata8 = <01020304 05060708>;\n"
	"\t\"empty array\" =\n"
	"\t(\n"
	"\t\t\n"
	"\t);\n"
	"\t\"empty dict\" =\n"
	"\t{\n"
	"\t\t\n"
	"\t};\n"
	"\thuge = 1e+300;\n"
	"\tname = \"Cobra Mk III\";\n"
	"\tnegative = -42;\n"
	"\tnegzero = -0;\n"
	"\tnested =\n"
	"\t(\n"
	"\t\ta,\n"
	"\t\t(\n"
	"\t\t\tb,\n"
	"\t\t\t{\n"
	"\t\t\t\tc = d;\n"
	"\t\t\t}\n"
	"\t\t)\n"
	"\t);\n"
	"\tno = false;\n"
	"\tratio = 0.1;\n"
	"\tthird = 0.33333333;\n"
	"\ttiny = 1e-07;\n"
	"\twhole = 100;\n"
	"\tyes = true;\n"
	"}\n"sv;
const std::string_view kW01Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<dict>\n"
	"    <key>big</key>\n"
	"    <integer>9223372036854775807</integer>\n"
	"    <key>count</key>\n"
	"    <integer>3</integer>\n"
	"    <key>data0</key>\n"
	"    <data>\n"
	"</data>\n"
	"    <key>data1</key>\n"
	"    <data>\n"
	"AQ==</data>\n"
	"    <key>data3</key>\n"
	"    <data>\n"
	"AQID</data>\n"
	"    <key>data4</key>\n"
	"    <data>\n"
	"AQIDBA==</data>\n"
	"    <key>data8</key>\n"
	"    <data>\n"
	"AQIDBAUGBwg=</data>\n"
	"    <key>empty array</key>\n"
	"    <array>\n"
	"    </array>\n"
	"    <key>empty dict</key>\n"
	"    <dict>\n"
	"    </dict>\n"
	"    <key>huge</key>\n"
	"    <real>1e+300</real>\n"
	"    <key>name</key>\n"
	"    <string>Cobra Mk III</string>\n"
	"    <key>negative</key>\n"
	"    <integer>-42</integer>\n"
	"    <key>negzero</key>\n"
	"    <real>-0</real>\n"
	"    <key>nested</key>\n"
	"    <array>\n"
	"\t<string>a</string>\n"
	"\t<array>\n"
	"\t    <string>b</string>\n"
	"\t    <dict>\n"
	"\t\t<key>c</key>\n"
	"\t\t<string>d</string>\n"
	"\t    </dict>\n"
	"\t</array>\n"
	"    </array>\n"
	"    <key>no</key>\n"
	"    <false/>\n"
	"    <key>ratio</key>\n"
	"    <real>0.1</real>\n"
	"    <key>third</key>\n"
	"    <real>0.3333333333333333</real>\n"
	"    <key>tiny</key>\n"
	"    <real>1e-07</real>\n"
	"    <key>whole</key>\n"
	"    <real>100</real>\n"
	"    <key>yes</key>\n"
	"    <true/>\n"
	"</dict>\n"
	"</plist>"sv;
const std::string_view kW03In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<dict>\n"
	"<key>b</key><string>1</string>\n"
	"<key>B</key><string>2</string>\n"
	"<key>a</key><string>3</string>\n"
	"<key>_</key><string>4</string>\n"
	"<key>Z</key><string>5</string>\n"
	"<key>[</key><string>6</string>\n"
	"<key>aa</key><string>7</string>\n"
	"<key>A</key><string>8</string>\n"
	"<key>10</key><string>9</string>\n"
	"<key>9</key><string>10</string>\n"
	"<key>~</key><string>11</string>\n"
	"</dict>\n"
	"</plist>\n"sv;
const std::string_view kW03Old =
	"{\n"
	"\t\"10\" = \"9\";\n"
	"\t\"9\" = \"10\";\n"
	"\t\"[\" = \"6\";\n"
	"\t\"_\" = \"4\";\n"
	"\tA = \"8\";\n"
	"\ta = \"3\";\n"
	"\taa = \"7\";\n"
	"\tB = \"2\";\n"
	"\tb = \"1\";\n"
	"\tZ = \"5\";\n"
	"\t\"~\" = \"11\";\n"
	"}\n"sv;
const std::string_view kW03Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<dict>\n"
	"    <key>10</key>\n"
	"    <string>9</string>\n"
	"    <key>9</key>\n"
	"    <string>10</string>\n"
	"    <key>A</key>\n"
	"    <string>8</string>\n"
	"    <key>B</key>\n"
	"    <string>2</string>\n"
	"    <key>Z</key>\n"
	"    <string>5</string>\n"
	"    <key>[</key>\n"
	"    <string>6</string>\n"
	"    <key>_</key>\n"
	"    <string>4</string>\n"
	"    <key>a</key>\n"
	"    <string>3</string>\n"
	"    <key>aa</key>\n"
	"    <string>7</string>\n"
	"    <key>b</key>\n"
	"    <string>1</string>\n"
	"    <key>~</key>\n"
	"    <string>11</string>\n"
	"</dict>\n"
	"</plist>"sv;
const std::string_view kW04In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array><date>2001-01-01 00:00:00 +0000</date></array>\n"
	"</plist>\n"sv;
const std::string_view kW04Old =
	"WRITEERR non-plist object in dictionary\n"sv;
const std::string_view kW04Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <date>2001-01-01T00:00:00Z</date>\n"
	"</array>\n"
	"</plist>"sv;
const std::string_view kW05In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<string>top</string>\n"
	"</plist>\n"sv;
const std::string_view kW05Old =
	"top\n"sv;
const std::string_view kW05Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<string>top</string>\n"
	"</plist>"sv;
const std::string_view kW06In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<integer>7</integer>\n"
	"</plist>\n"sv;
const std::string_view kW06Old =
	"7\n"sv;
const std::string_view kW06Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<integer>7</integer>\n"
	"</plist>"sv;
const std::string_view kW07In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<data>AQID</data>\n"
	"</plist>\n"sv;
const std::string_view kW07Old =
	"<010203>\n"sv;
const std::string_view kW07Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<data>\n"
	"AQID</data>\n"
	"</plist>"sv;
const std::string_view kW08In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array><array><array><array><array><array><array><array><array><array><array><array><array><array><string>deep</string></array></array></array></array></array></array></array></array></array></array></array></array></array></array>\n"
	"</plist>\n"sv;
const std::string_view kW08Old =
	"(\n"
	"\t(\n"
	"\t\t(\n"
	"\t\t\t(\n"
	"\t\t\t\t(\n"
	"\t\t\t\t\t(\n"
	"\t\t\t\t\t\t(\n"
	"\t\t\t\t\t\t\t(\n"
	"\t\t\t\t\t\t\t\t(\n"
	"\t\t\t\t\t\t\t\t\t(\n"
	"\t\t\t\t\t\t\t\t\t\t(\n"
	"\t\t\t\t\t\t\t\t\t\t\t(\n"
	"\t\t\t\t\t\t\t\t\t\t\t\t(\n"
	"\t\t\t\t\t\t\t\t\t\t\t\t\t(\n"
	"\t\t\t\t\t\t\t\t\t\t\t\t\t\tdeep\n"
	"\t\t\t\t\t\t\t\t\t\t\t\t\t)\n"
	"\t\t\t\t\t\t\t\t\t\t\t\t)\n"
	"\t\t\t\t\t\t\t\t\t\t\t)\n"
	"\t\t\t\t\t\t\t\t\t\t)\n"
	"\t\t\t\t\t\t\t\t\t)\n"
	"\t\t\t\t\t\t\t\t)\n"
	"\t\t\t\t\t\t\t)\n"
	"\t\t\t\t\t\t)\n"
	"\t\t\t\t\t)\n"
	"\t\t\t\t)\n"
	"\t\t\t)\n"
	"\t\t)\n"
	"\t)\n"
	")\n"sv;
const std::string_view kW08Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <array>\n"
	"\t<array>\n"
	"\t    <array>\n"
	"\t\t<array>\n"
	"\t\t    <array>\n"
	"\t\t\t<array>\n"
	"\t\t\t    <array>\n"
	"\t\t\t\t<array>\n"
	"\t\t\t\t    <array>\n"
	"\t\t\t\t\t<array>\n"
	"\t\t\t\t\t    <array>\n"
	"\t\t\t\t\t\t<array>\n"
	"\t\t\t\t\t\t<array>\n"
	"\t\t\t\t\t\t<string>deep</string>\n"
	"\t\t\t\t\t\t</array>\n"
	"\t\t\t\t\t\t</array>\n"
	"\t\t\t\t\t    </array>\n"
	"\t\t\t\t\t</array>\n"
	"\t\t\t\t    </array>\n"
	"\t\t\t\t</array>\n"
	"\t\t\t    </array>\n"
	"\t\t\t</array>\n"
	"\t\t    </array>\n"
	"\t\t</array>\n"
	"\t    </array>\n"
	"\t</array>\n"
	"    </array>\n"
	"</array>\n"
	"</plist>"sv;
const std::string_view kW09In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<dict><key>k</key><dict><key>j</key><array><integer>1</integer><dict/></array></dict></dict>\n"
	"</plist>\n"sv;
const std::string_view kW09Old =
	"{\n"
	"\tk =\n"
	"\t{\n"
	"\t\tj =\n"
	"\t\t(\n"
	"\t\t\t1,\n"
	"\t\t\t{\n"
	"\t\t\t\t\n"
	"\t\t\t}\n"
	"\t\t);\n"
	"\t};\n"
	"}\n"sv;
const std::string_view kW09Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<dict>\n"
	"    <key>k</key>\n"
	"    <dict>\n"
	"\t<key>j</key>\n"
	"\t<array>\n"
	"\t    <integer>1</integer>\n"
	"\t    <dict>\n"
	"\t    </dict>\n"
	"\t</array>\n"
	"    </dict>\n"
	"</dict>\n"
	"</plist>"sv;
const std::string_view kW10In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array><real>2.5e-310</real><real>123456789012345678</real><real>0.30000000000000004</real><real>inf</real><real>nan</real></array>\n"
	"</plist>\n"sv;
const std::string_view kW10Old =
	"(\n"
	"\t2.5e-310,\n"
	"\t1.2345679e+17,\n"
	"\t0.3,\n"
	"\tinf,\n"
	"\tnan\n"
	")\n"sv;
const std::string_view kW10Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <real>2.500000000000017e-310</real>\n"
	"    <real>1.234567890123457e+17</real>\n"
	"    <real>0.3</real>\n"
	"    <real>inf</real>\n"
	"    <real>nan</real>\n"
	"</array>\n"
	"</plist>"sv;
const std::string_view kW11In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<date>2024-02-29 12:34:56 -0800</date>\n"
	"</plist>\n"sv;
const std::string_view kW11Old =
	"WRITEERR Class NSCalendarDate does not support OldSchoolPropertyListWriting\n"sv;
const std::string_view kW11Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<date>2024-02-29T20:34:56Z</date>\n"
	"</plist>"sv;
const std::string_view kW02In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"<string></string>\n"
	"<string>abc</string>\n"
	"<string>ABC123</string>\n"
	"<string>9lives</string>\n"
	"<string>a_b</string>\n"
	"<string>with space</string>\n"
	"<string>quote\"back\\slash</string>\n"
	"<string>new\n"
	"line</string>\n"
	"<string>cr&#13;here</string>\n"
	"<string>tab\there</string>\n"
	"<string>caf\xc3\xa9</string>\n"
	"<string>&lt;tag&gt; &amp; &apos;q&apos;</string>\n"
	"<string>ctl&#1;&#31;</string>\n"
	"<string>\\UFFFE\\UFFFF</string>\n"
	"<string>&#x1F600;</string>\n"
	"<string>nul&#0;x</string>\n"
	"<string>nul&#0;&amp;</string>\n"
	"<string>\\UD800</string>\n"
	"</array>\n"
	"</plist>\n"sv;
const std::string_view kW02Old =
	"WRITEERR (nil)\n"sv;
const std::string_view kW02Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <string></string>\n"
	"    <string>abc</string>\n"
	"    <string>ABC123</string>\n"
	"    <string>9lives</string>\n"
	"    <string>a_b</string>\n"
	"    <string>with space</string>\n"
	"    <string>quote&quot;back\\slash</string>\n"
	"    <string>new\n"
	"line</string>\n"
	"    <string>cr\rhere</string>\n"
	"    <string>tab\there</string>\n"
	"    <string>caf\xc3\xa9</string>\n"
	"    <string>&lt;tag&gt; &amp; &apos;q&apos;</string>\n"
	"    <string>ctl\\U0001\\U001F</string>\n"
	"    <string>\\UFFFF</string>\n"
	"    <string>\xf0\x9f\x98\x80</string>\n"
	"    <string>nul\x00x</string>\n"
	"    <string>nul\\U0000&amp;</string>\n"
	"    <string></string>\n"
	"</array>\n"
	"</plist>"sv;
const std::string_view kV01In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"<string></string>\n"
	"<string>abc</string>\n"
	"<string>ABC123</string>\n"
	"<string>9lives</string>\n"
	"<string>a_b</string>\n"
	"<string>with space</string>\n"
	"<string>quote\"back\\slash</string>\n"
	"<string>new\n"
	"line</string>\n"
	"<string>cr&#13;here</string>\n"
	"<string>tab\there</string>\n"
	"<string>caf\xc3\xa9</string>\n"
	"<string>&lt;tag&gt; &amp; &apos;q&apos;</string>\n"
	"<string>ctl&#1;&#31;</string>\n"
	"<string>&#x1F600;</string>\n"
	"<string>nul&#0;x</string>\n"
	"<string>x&#xFEFF;</string>\n"
	"<string>a.b</string>\n"
	"<string>-1</string>\n"
	"<string>1.5</string>\n"
	"<string>yes</string>\n"
	"</array>\n"
	"</plist>\n"sv;
const std::string_view kV01Old =
	"(\n"
	"\t\"\",\n"
	"\tabc,\n"
	"\tABC123,\n"
	"\t\"9lives\",\n"
	"\t\"a_b\",\n"
	"\t\"with space\",\n"
	"\t\"quote\\\"\\\\slash\",\n"
	"\t\"new\\\n"
	"line\",\n"
	"\t\"cr\\\rhere\",\n"
	"\t\"tab\there\",\n"
	"\tcaf\xc3\xa9,\n"
	"\t\"<tag> & 'q'\",\n"
	"\t\"ctl\x01\x1f\",\n"
	"\t\"\xf0\x9f\x98\x80\",\n"
	"\t\"nul\x00x\",\n"
	"\tx,\n"
	"\t\"a.b\",\n"
	"\t\"-1\",\n"
	"\t\"1.5\",\n"
	"\tyes\n"
	")\n"sv;
const std::string_view kV01Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <string></string>\n"
	"    <string>abc</string>\n"
	"    <string>ABC123</string>\n"
	"    <string>9lives</string>\n"
	"    <string>a_b</string>\n"
	"    <string>with space</string>\n"
	"    <string>quote&quot;back\\slash</string>\n"
	"    <string>new\n"
	"line</string>\n"
	"    <string>cr\rhere</string>\n"
	"    <string>tab\there</string>\n"
	"    <string>caf\xc3\xa9</string>\n"
	"    <string>&lt;tag&gt; &amp; &apos;q&apos;</string>\n"
	"    <string>ctl\\U0001\\U001F</string>\n"
	"    <string>\xf0\x9f\x98\x80</string>\n"
	"    <string>nul\x00x</string>\n"
	"    <string>x</string>\n"
	"    <string>a.b</string>\n"
	"    <string>-1</string>\n"
	"    <string>1.5</string>\n"
	"    <string>yes</string>\n"
	"</array>\n"
	"</plist>"sv;
const std::string_view kV02In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<dict><key>a</key><string>1</string><key>A</key><string>2</string><key>ab</key><string>3</string><key>AB</key><string>4</string><key>Ab</key><string>5</string><key>aB</key><string>6</string><key>a1</key><string>7</string><key>a-</key><string>8</string></dict>\n"
	"</plist>\n"sv;
const std::string_view kV02Old =
	"{\n"
	"\tA = \"2\";\n"
	"\ta = \"1\";\n"
	"\t\"a-\" = \"8\";\n"
	"\ta1 = \"7\";\n"
	"\taB = \"6\";\n"
	"\tAB = \"4\";\n"
	"\tAb = \"5\";\n"
	"\tab = \"3\";\n"
	"}\n"sv;
const std::string_view kV02Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<dict>\n"
	"    <key>A</key>\n"
	"    <string>2</string>\n"
	"    <key>AB</key>\n"
	"    <string>4</string>\n"
	"    <key>Ab</key>\n"
	"    <string>5</string>\n"
	"    <key>a</key>\n"
	"    <string>1</string>\n"
	"    <key>a-</key>\n"
	"    <string>8</string>\n"
	"    <key>a1</key>\n"
	"    <string>7</string>\n"
	"    <key>aB</key>\n"
	"    <string>6</string>\n"
	"    <key>ab</key>\n"
	"    <string>3</string>\n"
	"</dict>\n"
	"</plist>"sv;
const std::string_view kV03In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array><date>0001-01-01 00:00:00 +0000</date><date>1999-12-31 23:59:59 +0000</date><date>2001-01-01 00:00:00 +0100</date><date>9999-12-31 23:59:59 +0000</date></array>\n"
	"</plist>\n"sv;
const std::string_view kV03Old =
	"WRITEERR non-plist object in dictionary\n"sv;
const std::string_view kV03Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <date>0001-01-01T00:00:00Z</date>\n"
	"    <date>1999-12-31T23:59:59Z</date>\n"
	"    <date>2000-12-31T23:00:00Z</date>\n"
	"    <date>9999-12-31T23:59:59Z</date>\n"
	"</array>\n"
	"</plist>"sv;
const std::string_view kV06In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<dict><key>k</key><dict><key>j</key><data>AAECAwQFBgc=</data></dict></dict>\n"
	"</plist>\n"sv;
const std::string_view kV06Old =
	"{\n"
	"\tk =\n"
	"\t{\n"
	"\t\tj = <00010203 04050607>;\n"
	"\t};\n"
	"}\n"sv;
const std::string_view kV06Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<dict>\n"
	"    <key>k</key>\n"
	"    <dict>\n"
	"\t<key>j</key>\n"
	"\t<data>\n"
	"AAECAwQFBgc=</data>\n"
	"    </dict>\n"
	"</dict>\n"
	"</plist>"sv;
const std::string_view kV07In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array><string>a</string><string>\\UD800</string></array>\n"
	"</plist>\n"sv;
const std::string_view kV07Old =
	"WRITEERR (nil)\n"sv;
const std::string_view kV07Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <string>a</string>\n"
	"    <string></string>\n"
	"</array>\n"
	"</plist>"sv;
const std::string_view kV08In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<dict><key>\\UDC00</key><string>v</string><key>w</key><string>x&#xFEFF;</string></dict>\n"
	"</plist>\n"sv;
const std::string_view kV08Old =
	"WRITEERR (nil)\n"sv;
const std::string_view kV08Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<dict>\n"
	"    <key>w</key>\n"
	"    <string>x</string>\n"
	"    <key></key>\n"
	"    <string>v</string>\n"
	"</dict>\n"
	"</plist>"sv;
const std::string_view kV09In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array><integer>0</integer><integer>-9223372036854775808</integer><real>1e16</real><real>123456.7</real><real>0.000012345678901</real></array>\n"
	"</plist>\n"sv;
const std::string_view kV09Old =
	"(\n"
	"\t0,\n"
	"\t-9223372036854775808,\n"
	"\t1e+16,\n"
	"\t123456.7,\n"
	"\t1.2345679e-05\n"
	")\n"sv;
const std::string_view kV09Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <integer>0</integer>\n"
	"    <integer>-9223372036854775808</integer>\n"
	"    <real>1e+16</real>\n"
	"    <real>123456.7</real>\n"
	"    <real>1.2345678901e-05</real>\n"
	"</array>\n"
	"</plist>"sv;
const std::string_view kW12In =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<plist version=\"1.0\">\n"
	"<array><data>AQIDBAU=</data></array>\n"
	"</plist>\n"sv;
const std::string_view kW12Old =
	"(\n"
	"\t<01020304 05\n"
	")\n"sv;
const std::string_view kW12Xml =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
	"<plist version=\"1.0\">\n"
	"<array>\n"
	"    <data>\n"
	"AQIDBAU=</data>\n"
	"</array>\n"
	"</plist>"sv;

oo::PList parsedOrNull(std::string_view in)
{
	oo::Expected<oo::PList, oo::PListError> r = oo::parsePropertyList(in);
	return r ? std::move(*r) : oo::PList();
}

std::string oldStyle(const oo::PList& p)
{
	oo::Expected<oo::Data, oo::PListError> r = oo::writeOldStylePList(p);
	return r ? r->toString() : "WRITEERR " + r.error().message + "\n";
}

std::string xml(const oo::PList& p)
{
	oo::Expected<oo::Data, oo::PListError> r = oo::writeXMLPList(p);
	return r ? r->toString() : "WRITEERR " + r.error().message + "\n";
}

// The fixture test: parse `in`, then both writers must produce GNUstep's bytes.
bool writesLikeGNUstep(std::string_view in, std::string_view expectedOld, std::string_view expectedXml)
{
	const oo::PList p = parsedOrNull(in);
	bool ok = OO_CHECK(!p.isNull());
	if (!expectedOld.empty()) ok = OO_CHECK_EQ(oldStyle(p), std::string(expectedOld)) && ok;
	ok = OO_CHECK_EQ(xml(p), std::string(expectedXml)) && ok;
	return ok;
}

} // namespace

OO_TEST(fixtureAllKinds)
{
	writesLikeGNUstep(kW01In, kW01Old, kW01Xml);   // every value type, nesting, data of 0-4 and 8 bytes
}

OO_TEST(fixtureStrings)
{
	// Bare vs quoted, escapes, controls, NUL, non-BMP. One line differs by design: GNUstep writes
	// caf\xc3\xa9 bare, oofnd quotes it (ADR-0027 item 5; oldStyleQuotesNonAscii_ADR0027).
	std::string v01Old(kV01Old);
	const std::size_t at = v01Old.find("\tcaf\xc3\xa9,");
	OO_CHECK(at != std::string::npos);
	if (at != std::string::npos) v01Old.replace(at, 7, "\t\"caf\xc3\xa9\",");
	writesLikeGNUstep(kV01In, v01Old, kV01Xml);
	// With a lone surrogate among them GNUstep's old-style writer returns nil (no description) and
	// the XML writer drops that string's text.
	writesLikeGNUstep(kW02In, "", kW02Xml);
	OO_CHECK_EQ(kW02Old, "WRITEERR (nil)\n"sv);
	OO_CHECK(!oo::writeOldStylePList(parsedOrNull(kW02In)).has_value());
	writesLikeGNUstep(kV07In, "", kV07Xml);
	OO_CHECK(!oo::writeOldStylePList(parsedOrNull(kV07In)).has_value());
	writesLikeGNUstep(kV08In, "", kV08Xml);   // ... a lone-surrogate key too
	OO_CHECK(kV07Old == kW02Old && kV08Old == kW02Old);
}

OO_TEST(fixtureKeyOrder)
{
	writesLikeGNUstep(kW03In, kW03Old, kW03Xml);   // old-style: case-insensitive; XML: by UTF-16 unit
	writesLikeGNUstep(kV02In, "", kV02Xml);
}

OO_TEST(fixtureScalarsAtTopLevel)
{
	writesLikeGNUstep(kW05In, kW05Old, kW05Xml);
	writesLikeGNUstep(kW06In, kW06Old, kW06Xml);
	writesLikeGNUstep(kW07In, kW07Old, kW07Xml);
}

OO_TEST(fixtureNestingAndIndentation)
{
	writesLikeGNUstep(kW08In, kW08Old, kW08Xml);   // XML indentation caps at six tabs
	writesLikeGNUstep(kW09In, kW09Old, kW09Xml);
	writesLikeGNUstep(kV06In, kV06Old, kV06Xml);   // 8 bytes of data at depth 2
}

OO_TEST(fixtureNumbers)
{
	writesLikeGNUstep(kW10In, kW10Old, kW10Xml);   // %.8g vs %.16g, subnormal, inf, nan
	writesLikeGNUstep(kV09In, kV09Old, kV09Xml);
}

OO_TEST(fixtureDates)
{
	// Old-style cannot write dates; XML writes them in UTC.
	writesLikeGNUstep(kW04In, kW04Old, kW04Xml);
	writesLikeGNUstep(kW11In, kW11Old, kW11Xml);
	writesLikeGNUstep(kV03In, kV03Old, kV03Xml);
}

OO_TEST(oldStyleDataGNUstepCannotWrite_ADR0027)
{
	// 5 bytes: GNUstep writes past its buffer and cuts the '>' (captured: "<01020304 05").
	OO_CHECK_EQ(kW12Old, "(\n\t<01020304 05\n)\n"sv);
	OO_CHECK_EQ(oldStyle(parsedOrNull(kW12In)), "(\n\t<01020304 05>\n)\n");
	OO_CHECK_EQ(xml(parsedOrNull(kW12In)), std::string(kW12Xml));
	// More than 32 bytes: GNUstep crashes; oofnd breaks the line every 32 bytes.
	oo::PList::Data bytes;
	for (int i = 0; i < 40; ++i) bytes.append(&i, 1);
	OO_CHECK_EQ(oldStyle(oo::PList(oo::PList::Array{oo::PList(bytes)})),
				"(\n\t<00010203 04050607 08090A0B 0C0D0E0F 10111213 14151617 18191A1B 1C1D1E1F\n"
				" 20212223 24252627>\n)\n");
	OO_CHECK_EQ(oldStyle(oo::PList(oo::PList::Dict{{"k", oo::PList(oo::PList::Dict{{"j", oo::PList(bytes)}})}})),
				"{\n\tk =\n\t{\n\t\tj = <00010203 04050607 08090A0B 0C0D0E0F 10111213 14151617 18191A1B 1C1D1E1F\n"
				"\t 20212223 24252627>;\n\t};\n}\n");
}

OO_TEST(oldStyleQuotesNonAscii_ADR0027)
{
	// GNUstep writes `caf\xc3\xa9` bare (it is "alphanumeric"), which no plist reader accepts.
	OO_CHECK(kV01Old.find("\tcaf\xc3\xa9,") != std::string_view::npos);
	OO_CHECK_EQ(oldStyle(oo::PList("caf\xc3\xa9")), "\"caf\xc3\xa9\"\n");
	OO_CHECK_EQ(oldStyle(oo::PList("cafe")), "cafe\n");
}

OO_TEST(oldStyleKeysEqualButForCase_ADR0027)
{
	// GNUstep orders these by hash (captured: A, a, a-, a1, aB, AB, Ab, ab); oofnd by UTF-16 unit.
	OO_CHECK(kV02Old.find("\ta1 = \"7\";\n\taB = \"6\";\n\tAB = \"4\";") != std::string_view::npos);
	OO_CHECK_EQ(oldStyle(parsedOrNull(kV02In)),
				"{\n\tA = \"2\";\n\ta = \"1\";\n\t\"a-\" = \"8\";\n\ta1 = \"7\";\n\tAB = \"4\";\n\tAb = \"5\";\n\taB = \"6\";\n\tab = \"3\";\n}\n");
}

OO_TEST(writersOnHandBuiltValues)
{
	using oo::PList;
	OO_CHECK_EQ(oldStyle(PList(PList::Dict{})), "{\n\t\n}\n");
	OO_CHECK_EQ(oldStyle(PList(PList::Array{})), "(\n\t\n)\n");
	OO_CHECK_EQ(oldStyle(PList::unsignedInteger(18446744073709551615ull)), "18446744073709551615\n");
	OO_CHECK_EQ(oldStyle(PList(true)), "true\n");
	OO_CHECK_EQ(oldStyle(PList("")), "\"\"\n");
	// OldSchoolPropertyListWriting drops the text between two escaped characters (fixture V01
	// pins it: "quote\"back\\slash" is written "quote\"\\slash").
	OO_CHECK_EQ(oldStyle(PList("a\"b\\c\nd\re\tf")), "\"a\\\"\\\\\\\n\\\re\tf\"\n");
	OO_CHECK_EQ(oldStyle(PList("one \"escape\" only")), "\"one \\\"\\\" only\"\n");
	OO_CHECK_EQ(oldStyle(PList("tail\n")), "\"tail\\\n\"\n");
	OO_CHECK_EQ(oldStyle(PList("\\\\")), "\"\\\\\\\\\"\n");
	OO_CHECK_EQ(oldStyle(PList()), "WRITEERR nil property list\n");
	OO_CHECK_EQ(oldStyle(PList(PList::Array{PList()})), "WRITEERR non-plist object in dictionary\n");
	OO_CHECK_EQ(xml(PList()), "WRITEERR nil property list\n");
	// A leading U+FEFF survives the raw path but not XString's escaping path (an NSString made
	// from units); captured from GNUstep: "﻿&" writes as "&amp;".
	OO_CHECK_EQ(xml(PList("\xEF\xBB\xBF&")).find("<string>&amp;</string>") != std::string::npos, true);
	OO_CHECK_EQ(xml(PList("\xEF\xBB\xBFx")).find("<string>\xEF\xBB\xBFx</string>") != std::string::npos, true);
}

OO_TEST(roundTrips)
{
	using oo::PList;
	// XML keeps every kind (non-negative integers read back unsigned, as GNUstep stores them).
	const PList all(PList::Dict{
		{"s", PList("text & <markup> \"q\" 'a' \\ caf\xc3\xa9 \xF0\x9F\x98\x80")},
		{"i", PList::unsignedInteger(42)},
		{"n", PList::signedInteger(-7)},
		{"r", PList(0.1)},
		{"t", PList(true)},
		{"f", PList(false)},
		{"d", PList(oo::Data("\x00\x01\xff", 3))},
		{"date", PList(PList::Date{730931696.0})},
		{"a", PList(PList::Array{PList("x"), PList(PList::Array{}), PList(PList::Dict{})})},
	});
	const oo::Expected<oo::Data, oo::PListError> x = oo::writeXMLPList(all);
	OO_CHECK(x.has_value());
	OO_CHECK(oo::parsePropertyList(x->stringView()).value() == all);

	// Old-style keeps strings, data, arrays and dictionaries (numbers come back as strings).
	const PList text(PList::Dict{
		{"bare", PList("word")},
		{"quoted", PList("two words; one \"quote")},   // (text between escapes would be lost)
		{"escapes", PList("\\\n\"\r")},
		{"data", PList(oo::Data("\x01\x02\x03\x04", 4))},
		{"list", PList(PList::Array{PList("a"), PList("9"), PList(PList::Dict{{"k", PList("v")}})})},
		{"Upper", PList("")},
	});
	const oo::Expected<oo::Data, oo::PListError> o = oo::writeOldStylePList(text);
	OO_CHECK(o.has_value());
	OO_CHECK(oo::parsePropertyList(o->stringView()).value() == text);
	OO_CHECK_EQ(oo_test::dump(oo::parsePropertyList(oldStyle(PList(PList::Array{PList(1), PList(2.5), PList(true)}))).value()),
				"[S\"1\",S\"2.5\",S\"true\"]");
}

OO_TEST(parsePropertyListDispatch)
{
	oo::PListFormat f = oo::PListFormat::Binary;
	OO_CHECK_EQ(oo_test::dump(oo::parsePropertyList("{ a = b; }", &f).value()), "{\"a\"=S\"b\";}");
	OO_CHECK(f == oo::PListFormat::OpenStep);
	OO_CHECK_EQ(oo_test::dump(oo::parsePropertyList(" \n<*I5>", &f).value()), "I5");
	OO_CHECK(f == oo::PListFormat::GNUstep);
	OO_CHECK_EQ(oo_test::dump(oo::parsePropertyList("<?xml version=\"1.0\"?><plist><true/></plist>", &f).value()), "B1");
	OO_CHECK(f == oo::PListFormat::XML);
	// Whitespace before "<?" still selects XML, whose scanner then rejects it (captured).
	OO_CHECK_EQ(oo::parsePropertyList("  <?xml version=\"1.0\"?><plist><true/></plist>", &f).error().message,
				"failed to parse as XML property list");
	OO_CHECK(f == oo::PListFormat::XML);
	OO_CHECK_EQ(oo::parsePropertyList("").error().message, "empty data argument passed to method");
	OO_CHECK_EQ(oo::parsePropertyList("{ a = b ").error().message, "Parse failed at line 1 (char 9) - reached end of string");
	OO_CHECK_EQ(oo::parsePropertyList("{ a = b ").error().description(),
				"Error Domain=NSPropertyListSerialization Code=0 \"Parse failed at line 1 (char 9) - reached end of string\"");
	// Binary plists are not read (ADR-0027 item 3).
	OO_CHECK(!oo::parsePropertyList("bplist00\x01\x02"sv, &f).has_value());
	OO_CHECK(f == oo::PListFormat::Binary);
	OO_CHECK(!oo::parsePropertyList("\x00\x01"sv, &f).has_value());
	OO_CHECK(f == oo::PListFormat::GNUstepBinary);
	// The DTD change is applied first (OOPropertyListFromData), and is transparent.
	OO_CHECK(oo::parsePropertyList(kW01In).value() == oo::parsePropertyListData(kW01In).value());
}

OO_TEST_MAIN()
