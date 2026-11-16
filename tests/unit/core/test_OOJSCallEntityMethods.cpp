/*	test_OOJSCallEntityMethods.mm
        Unit tests for callObjC()'s entity name table
   (src/Core/Scripting/OOJSCallEntityMethods.h, generated).

        The oracle is the signature matcher callObjC() used for an entity's
   object before the table (OOJSCall.mm's GetMethodType(), whose templates were
   the deleted bridge's template methods: void/void, void/const std::string &,
   oo::PList/const std::string &, oo::PList/void, else the shader uniform type
   of the return type). Its safe set on the root facade's own methods (the class
   Entity, with every category; not its superclasses) is the selectors it
   matched with no argument or with one of the two string templates, less the
   lifetime and root-protocol names and the compiler's
   .cxx_construct/.cxx_destruct. The table must list exactly that set, and each
   row must classify its method as the matcher did. The facade is the real one,
   so the test links the whole game but main (['*']). The facade's five by-name
   categories are the C++ by-name table
   (OOEntityCalledByNameTable.h): the oracle adds its rows, each classified
   as the matcher classified the category method, from the row's declared result
   and argument (the encodings the method had; test_OOEntityCalledByName checked
   them against the methods until then). Run: tests/run.sh unit
*/

#include <cstdlib>
#include <cstring>
#include <iterator>
#include <map>
#include <optional>
#include <set>
#include <string>

#include "OOEntityCalledByName.h"
#include "OOJSCallEntityMethods.h"
#include "OOShaderUniformMethodType.h"
#include "oo_test.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

namespace {

// The names the generator leaves out.
const std::set<std::string> kExcluded = {
    "init",        "dealloc",     "finalize", "retain",      "release",
    "autorelease", "retainCount", "copy",     "mutableCopy", "self",
    "class",       "superclass",  "hash",     "description", "debugDescription",
    "isProxy",     "zone",
};

struct OracleRow {
  OOJSCallEntityMethodForm form;
  OOShaderUniformType type;  // a Typed row's
};

// The matcher's classification of a by-name row's method (its declared result
// and argument).
std::optional<OracleRow> Oracle(const OOEntityByNameRow& row) {
  const bool voidResult = std::strcmp(row.result, kOOTypeEncoding<void>) == 0;
  const bool plistResult =
      std::strcmp(row.result, kOOTypeEncoding<oo::PList>) == 0;
  switch (row.argument) {
    case OOEntityByNameArgument::None:
      if (voidResult)
        return OracleRow{OOJSCallEntityMethodForm::VoidVoid,
                         kOOShaderUniformTypeInvalid};
      if (plistResult)
        return OracleRow{OOJSCallEntityMethodForm::PListVoid,
                         kOOShaderUniformTypeInvalid};
      return OracleRow{OOJSCallEntityMethodForm::Typed,
                       OOShaderUniformTypeFromEncoding(row.result)};
    case OOEntityByNameArgument::String:
      if (voidResult)
        return OracleRow{OOJSCallEntityMethodForm::VoidString,
                         kOOShaderUniformTypeInvalid};
      if (plistResult)
        return OracleRow{OOJSCallEntityMethodForm::PListString,
                         kOOShaderUniformTypeInvalid};
      return std::nullopt;  // called with its argument missing
    case OOEntityByNameArgument::PList:
      return std::nullopt;  // an argument the templates do not take
  }
  return std::nullopt;
}

// The safe set's by-name rows.
std::map<std::string, OracleRow> OracleSafeSet() {
  std::map<std::string, OracleRow> result;
  for (const OOEntityByNameRow& row : oo::EntityByNameRows()) {
    std::string bare = row.name;
    if (!bare.empty() && bare.back() == ':') bare.pop_back();
    if (kExcluded.contains(bare)) continue;
    if (std::optional<OracleRow> oracle = Oracle(row))
      result[row.name] = *oracle;
  }
  return result;
}

}  // namespace

OO_TEST(tableIsTheMatchersSafeSet) {
  {
    const std::map<std::string, OracleRow> oracle = OracleSafeSet();
    std::map<std::string, const OOJSCallEntityMethodRow*> table;
    for (const OOJSCallEntityMethodRow& row : kOOJSCallEntityMethods)
      table[row.name] = &row;
    OO_CHECK_EQ(table.size(),
                std::size(kOOJSCallEntityMethods));  // no name twice
    OO_CHECK(oracle.size() > 400);                   // the by-name categories

    std::string missing, different;
    for (const auto& [name, row] : oracle) {
      auto found = table.find(name);
      if (found == table.end()) {
        missing += " " + name;
        continue;
      }
      const OOJSCallEntityMethodRow& entry = *found->second;
      bool same = (entry.form == row.form);
      if (same && row.form == OOJSCallEntityMethodForm::Typed)
        same = (OOShaderUniformTypeFromEncoding(entry.encoding) == row.type);
      if (!same) different += " " + name;
    }
    OO_CHECK_EQ(missing, std::string());
    OO_CHECK_EQ(different, std::string());
  }
}

// The safe set leaves out what callObjC() could not call safely: lifetime and
// root-protocol names, and every selector with an argument but the two string
// templates.
OO_TEST(tableLeavesOutUnsafeNames) {
  std::set<std::string> names;
  for (const OOJSCallEntityMethodRow& row : kOOJSCallEntityMethods)
    names.insert(row.name);
  for (const char* name :
       {"init", "dealloc", "retain", "release", "autorelease", "copy", "self",
        "class", "hash", "description",
        "respondsToSelector:", "isKindOfClass:", "initWithCxxEntity:"}) {
    OO_CHECK(!names.contains(name));
  }
  for (const OOJSCallEntityMethodRow& row : kOOJSCallEntityMethods) {
    const bool takesString =
        (row.form == OOJSCallEntityMethodForm::VoidString ||
         row.form == OOJSCallEntityMethodForm::PListString);
    const bool endsWithColon = (std::strlen(row.name) > 0 &&
                                row.name[std::strlen(row.name) - 1] == ':');
    OO_CHECK(takesString == endsWithColon);
    OO_CHECK((row.form == OOJSCallEntityMethodForm::Typed) ==
             (row.encoding != nullptr));
  }
}

// callObjC() asks and calls an entity's C++ part for every name of its table:
// each name is a by-name row or a facade row
// (OOEntityCalledByName.mm), never both; each facade row is a method of the
// root facade (the class Entity, with its categories), and has the facade
// method's body exactly when callObjC() can read the method's result.
OO_TEST(everyNameIsAnsweredByTheCxxEntity) {
  {
    std::set<std::string> names;
    for (const OOJSCallEntityMethodRow& row : kOOJSCallEntityMethods)
      names.insert(row.name);

    std::string uncovered, twice, notInTable, typedMismatch;
    for (const OOJSCallEntityMethodRow& row : kOOJSCallEntityMethods) {
      const bool byName = (oo::EntityByNameRowNamed(row.name) != nullptr);
      const OOEntityFacadeRow* facade = oo::EntityFacadeRowNamed(row.name);
      if (!byName && facade == nullptr)
        uncovered += std::string(" ") + row.name;
      if (byName && facade != nullptr) twice += std::string(" ") + row.name;
      if (facade == nullptr) continue;
      if (row.form != OOJSCallEntityMethodForm::Typed) {
        if (facade->typed == nullptr)
          typedMismatch += std::string(" ") + row.name;
        continue;
      }
      switch (OOShaderUniformTypeFromEncoding(row.encoding)) {
        case kOOShaderUniformTypeInvalid:
        case kOOShaderUniformTypeHPVector:
        case kOOShaderUniformTypeMatrix:
        case kOOShaderUniformTypePoint:
          break;  // callObjC() reads no result: a body is optional
        default:
          if (facade->typed == nullptr)
            typedMismatch += std::string(" ") + row.name;
      }
    }
    for (const OOEntityFacadeRow& facade : oo::EntityFacadeRows()) {
      if (!names.contains(facade.name))
        notInTable += std::string(" ") + facade.name;
    }
    OO_CHECK_EQ(uncovered, std::string());
    OO_CHECK_EQ(twice, std::string());
    OO_CHECK_EQ(notInTable, std::string());
    OO_CHECK_EQ(typedMismatch, std::string());
  }
}

OO_TEST_MAIN()
