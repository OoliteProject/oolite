/*	tests/unit/oofnd/oo_test.hpp
	The oofnd unit tests' whole test harness: a registry of named test functions and a CHECK
	macro. Plain C++20, header-only, no third-party framework (none is vendored in the tree).

	    #include "oo_test.hpp"
	    OO_TEST(somethingWorks) { OO_CHECK(1 + 1 == 2); OO_CHECK_EQ(f(), 3); }
	    OO_TEST_MAIN()

	Each test_*.cpp is its own executable. It prints one line per failed check and a summary line

	    oo_test: <file>: <tests> tests, <checks> checks, <failures> failures

	which tools/check-oofnd.sh parses to total the test counts. The exit status is nonzero if any
	check failed OR if the file registered no tests at all, so an empty or mis-registered suite
	fails loudly instead of passing vacuously.
*/

#ifndef OOFND_TESTS_OO_TEST_HPP
#define OOFND_TESTS_OO_TEST_HPP

#include <cstdio>
#include <vector>

namespace oo_test {

struct Case
{
	const char* name;
	void (*fn)();
};

inline std::vector<Case>& registry()
{
	static std::vector<Case> cases;
	return cases;
}

inline int& failures()
{
	static int n = 0;
	return n;
}

inline int& checks()
{
	static int n = 0;
	return n;
}

inline const char*& currentTest()
{
	static const char* name = "";
	return name;
}

struct Registrar
{
	Registrar(const char* name, void (*fn)()) { registry().push_back(Case{name, fn}); }
};

inline bool check(bool ok, const char* expr, const char* file, int line)
{
	++checks();
	if (!ok)
	{
		++failures();
		std::printf("FAIL %s:%d [%s]: %s\n", file, line, currentTest(), expr);
	}
	return ok;
}

inline int runAll(const char* file)
{
	const std::vector<Case>& cases = registry();
	for (const Case& c : cases)
	{
		currentTest() = c.name;
		const int before = failures();
		c.fn();
		std::printf("%s %s\n", failures() == before ? "ok  " : "FAIL", c.name);
	}
	std::printf("oo_test: %s: %zu tests, %d checks, %d failures\n", file, cases.size(), checks(), failures());
	if (cases.empty())
	{
		std::printf("FAIL %s: no tests registered\n", file);
		return 2;
	}
	return failures() == 0 ? 0 : 1;
}

} // namespace oo_test

#define OO_TEST(name) \
	static void name(); \
	static const ::oo_test::Registrar name##_registrar(#name, &name); \
	static void name()

#define OO_CHECK(cond) ::oo_test::check(static_cast<bool>(cond), #cond, __FILE__, __LINE__)
#define OO_CHECK_EQ(a, b) ::oo_test::check((a) == (b), #a " == " #b, __FILE__, __LINE__)

#define OO_TEST_MAIN() \
	int main() { return ::oo_test::runAll(__FILE__); }

#endif // OOFND_TESTS_OO_TEST_HPP
