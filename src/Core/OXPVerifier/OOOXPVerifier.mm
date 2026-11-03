/*

OOOXPVerifier.m


Copyright (C) 2007-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

/*	Design notes:
        see "verifier design.txt".
*/

#import "OOOXPVerifier.h"
#import <objc/objc-arc.h>
#import <objc/runtime.h>

#if OO_OXP_VERIFIER_ENABLED

#if OOLITE_WINDOWS

#ifdef __OBJC__
#pragma push_macro("interface")
#undef interface
#define interface struct
#endif

#include <shlwapi.h>

#ifdef __OBJC__
#pragma pop_macro("interface")
#endif

#include <tchar.h>
#endif

#import "GameController.h"
#import "OOCacheManager.h"
#import "OODebugStandards.h"
#import "OOFoundationBridge.h"
#import "OOLoggingExtended.h"
#import "OOOXPVerifierStageInternal.h"
#import "OOPListView.h"
#import "ResourceManager.h"
#include "oofnd/Date.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/Process.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OORuntime.h"

namespace {
void SwitchLogFile(const std::string& name);
void NoteVerificationStage(const std::string& displayName, const std::string& stage);
void OpenLogFile();
}

@interface OOOXPVerifier (OOPrivate)

- (id)initWithPath:(id)path; // path: an Objective-C string. Shared selector (proposed ADR-0043).
- (void)run;

- (void)setUpLogOverrides;

- (void)registerBaseStages;
- (void)buildDependencyGraph;
- (void)runStages;

- (BOOL)setUpDependencies:(const std::vector<std::string>&)dependencies
                 forStage:(OOOXPVerifierStage*)stage;

- (void)setUpDependents:(const std::vector<std::string>&)dependents
               forStage:(OOOXPVerifierStage*)stage;

- (void)dumpDebugGraphviz;

@end

@implementation OOOXPVerifier

/**
 * \ingroup cli
 * Scans the command line for -verify-oxp or --verify-oxp, followed by a
 * path to the oxp to verify.
 *
 * @return YES or NO
 */
+ (BOOL)runVerificationIfRequested
{
    std::optional<std::string> foundPath;
    BOOL exists, isDirectory;
    OOOXPVerifier* verifier = nil;
    void* pool = NULL;

    pool = objc_autoreleasePoolPush();

    const std::vector<std::string>& arguments = oo::process::arguments();

    // Scan for -verify-oxp or --verify-oxp followed by relative path
    for (size_t argIndex = 0; argIndex < arguments.size(); argIndex++) {
        const std::string& arg = arguments[argIndex];
        if (arg == "-verify-oxp" || arg == "--verify-oxp") {
            if (argIndex + 1 < arguments.size())
                foundPath = arguments[argIndex + 1];
            if (!foundPath.has_value()) {
                OOLog(@"verifyOXP.noPath", @"***** ERROR: %s passed without path argument; nothing to verify.", arg.c_str());
                objc_autoreleasePoolPop(pool);
                return YES;
            }
            foundPath = oo::StdString([oo::NSStringFrom(*foundPath) stringByExpandingTildeInPath]); // no oo::str form yet: runs on the bridged string
            break;
        }
    }

    if (!foundPath.has_value()) {
        objc_autoreleasePoolPop(pool);
        return NO;
    }

    // We got a path; does it point to a directory?
    oo::fs::FileType foundType = oo::fs::fileType(oo::fs::pathFromUTF8(*foundPath));
    exists = (foundType != oo::fs::FileType::none);
    isDirectory = (foundType == oo::fs::FileType::directory);
    if (!exists) {
        OOLog(@"verifyOXP.badPath", @"***** ERROR: no OXP exists at path \"%@\"; nothing to verify.", oo::NSStringFrom(*foundPath));
    } else if (!isDirectory) {
        OOLog(@"verifyOXP.badPath", @"***** ERROR: \"%@\" is a file, not an OXP directory; nothing to verify.", oo::NSStringFrom(*foundPath));
    } else {
        verifier = [[OOOXPVerifier alloc] initWithPath:oo::NSStringFrom(*foundPath)];
        objc_autoreleasePoolPop(pool);
        pool = objc_autoreleasePoolPush();
        [verifier run];
        [verifier release];
    }
    objc_autoreleasePoolPop(pool);

    // Whether or not we got a valid path, -verify-oxp was passed.
    return YES;
}

- (void)dealloc
{
    // The C++ ivars (the configuration, the strings, the retained stages) are destroyed with the object.
    [super dealloc];
}

- (void)registerStage:(OOOXPVerifierStage*)stage
{
    id name = nil;
    OOOXPVerifierStage* existing = nil;

    // Sanity checking
    if (stage == nil)
        return;

    if (![stage isKindOfClass:[OOOXPVerifierStage class]]) {
        OOLog(@"verifyOXP.registration.failed", @"Attempt to register class %@ as a verifier stage, but it is not a subclass of OOOXPVerifierStage; ignoring.", [stage class]);
        return;
    }

    if (!_openForRegistration) {
        OOLog(@"verifyOXP.registration.failed", @"Attempt to register verifier stage %@ after registration closed, ignoring.", stage);
        return;
    }

    name = [stage name];
    if (name == nil) {
        OOLog(@"verifyOXP.registration.failed", @"Attempt to register verifier stage %@ with nil name, ignoring.", stage);
        return;
    }

    // We can only have one stage with a given name. Registering the same stage twice is OK, though.
    const auto found = _stagesByName.find(oo::StdString(name));
    existing = found != _stagesByName.end() ? found->second.get() : nil;
    if (existing == stage)
        return;
    if (existing != nil) {
        OOLog(@"verifyOXP.registration.failed", @"Attempt to register verifier stage %@ with same name as stage %@, ignoring.", stage, existing);
        return;
    }

    // Checks passed, store state.
    [stage setVerifier:self];
    _stagesByName[oo::StdString(name)] = oo::ObjCRef<OOOXPVerifierStage*>(stage);
    _waitingStages.push_back(oo::ObjCRef<OOOXPVerifierStage*>(stage));
}

- (std::optional<std::string>)cxx_oxpPath
{
    return _basePath;
}

- (std::optional<std::string>)cxx_oxpDisplayName
{
    return _displayName;
}

- (id)cxx_stageWithName:(const std::string&)name
{
    const auto found = _stagesByName.find(name);
    return found != _stagesByName.end() ? found->second.get() : nil;
}

- (id)configurationValueForKey:(id)key // shared selector (proposed ADR-0043)
{
    const oo::PList* value = _verifierPList.find(oo::StdString(key));
    return value != nullptr ? oo::ObjectFromPList(*value) : nil;
}

- (oo::PList)cxx_configurationArrayForKey:(const std::string&)key
{
    const oo::PList* array = _verifierPList.get<oo::PList::Array>(key);
    return array != nullptr ? *array : oo::PList();
}

- (oo::PList)cxx_configurationDictionaryForKey:(const std::string&)key
{
    const oo::PList* dictionary = _verifierPList.get<oo::PList::Dict>(key);
    return dictionary != nullptr ? *dictionary : oo::PList();
}

- (std::optional<std::string>)cxx_configurationStringForKey:(const std::string&)key
{
    const oo::PList* value = _verifierPList.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return _verifierPList.get<std::string>(key);
}

- (std::optional<std::vector<std::string>>)cxx_configurationSetForKey:(const std::string&)key
{
    const oo::PList* array = _verifierPList.get<oo::PList::Array>(key);
    if (array == nullptr)
        return std::nullopt;

    std::set<std::string> strings;
    for (const oo::PList& element : *array->getIf<oo::PList::Array>()) {
        if (const std::string* string = element.getIf<std::string>())
            strings.insert(*string);
    }
    return std::vector<std::string>(strings.begin(), strings.end());
}

@end

@implementation OOOXPVerifier (OOPrivate)

- (id)initWithPath:(id)path // shared selector (proposed ADR-0043)
{
    self = [super init];

    OOSetStandardsForOXPVerifierMode();

    // Any plist format; missing, unreadable or not a dictionary is no configuration, as
    // -dictionaryWithContentsOfFile: returned nil for them.
    const std::optional<std::string> builtInPath = [ResourceManager cxx_builtInPath];
    if (builtInPath.has_value()) {
        const std::string verifierPListPath = oo::str::appendingPathComponent(oo::str::appendingPathComponent(*builtInPath, "Config"), "verifyOXP.plist");
        if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(oo::fs::pathFromUTF8(verifierPListPath)); bytes && !bytes->empty()) {
            oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
            if (parsed && parsed->isDict())
                _verifierPList = std::move(*parsed);
        }
    }

    _basePath = oo::StdString(path); // never nil: the path always came from the command line
    _displayName = oo::str::lastPathComponent(_basePath); // what GNUstep's -displayNameAtPath: returns

    if (_verifierPList.isNull()) {
        OOLog(@"verifyOXP.setup.failed", @"%@", @"***** ERROR: failed to set up OXP verifier.");
        [self release];
        return nil;
    }

    _openForRegistration = YES;

    return self;
}

- (void)run
{
    NoteVerificationStage(_displayName, "");

    [self setUpLogOverrides];

    /*	We need to be able to look up internal files, but not other OXP files.
            To do this without clobbering the disk cache, we disable cache writes.
    */
    [[OOCacheManager sharedCache] flush];
    [[OOCacheManager sharedCache] setAllowCacheWrites:NO];
    /* FIXME: the OXP verifier should load files from OXPs which have
     * been explicitly listed as required_oxps in the
     * manifest. Reading the manifest from the OXP being verified and
     * setting 'id:<its identifier>' below will do this. */
    [ResourceManager setUseAddOns:SCENARIO_OXP_DEFINITION_NONE];

    SwitchLogFile(_displayName);
    OOLog(@"verifyOXP.start", @"Running OXP verifier for %@", oo::NSStringFrom(_basePath)); //_displayName);

    [self registerBaseStages];
    [self buildDependencyGraph];
    [self runStages];

    NoteVerificationStage(_displayName, "");
    OOLog(@"verifyOXP.done", @"%@", @"OXP verification complete.");

    OpenLogFile();
}

- (void)setUpLogOverrides
{
    id verbose = nil;

    OOLogSetShowMessageClassTemporary(oo::PListView(_verifierPList).get<bool>(@"logShowMessageClassOverride", NO));

    overrides = oo::PListView(_verifierPList).get<NSDictionary*>(@"logControlOverride");
    foreachkey(messageClass, overrides)
    {
        OOLogSetDisplayMessagesInClass(messageClass, oo::PListView(overrides).get<bool>(messageClass, NO));
    }

    /*	Since actually editing logControlOverride is a pain, we also allow
            overriding verifyOXP.verbose through user defaults. This is at least
            as much a pain under GNUstep, but very convenient under OS X.
    */
    verbose = [[NSUserDefaults standardUserDefaults] objectForKey:@"oxp-verifier-verbose-logging"];
    if (verbose != nil)
        OOLogSetDisplayMessagesInClass(@"verifyOXP.verbose", OOBooleanFromObject(verbose, NO));
}

- (void)registerBaseStages
{
    Class stageClass = Nil;
    OOOXPVerifierStage* stage = nil;

    @autoreleasepool {
        // Load stages specified as array of class names in verifyOXP.plist
        std::vector<std::string> stages = [self cxx_configurationSetForKey:"stages"].value_or(std::vector<std::string>());
        const std::vector<std::string> excludeStages = [self cxx_configurationSetForKey:"excludeStages"].value_or(std::vector<std::string>());
        if (!excludeStages.empty()) {
            std::erase_if(stages, [&excludeStages](const std::string& stageName) { return std::binary_search(excludeStages.begin(), excludeStages.end(), stageName); });
        }
        for (const std::string& stageName : stages) {
            stageClass = OOClassFromName(stageName);
            if (stageClass == Nil) {
                OOLog(@"verifyOXP.registration.failed", @"Attempt to register unknown class %@ as a verifier stage, ignoring.", oo::NSStringFrom(stageName));
                continue;
            }
            stage = [[stageClass alloc] init];
            [self registerStage:stage];
            [stage release];
        }
    }
}

- (void)buildDependencyGraph
{
    OOOXPVerifierStage* stage = nil;
    id name = nil;
    std::map<OOOXPVerifierStage*, std::vector<std::string>> dependenciesByStage,
        dependentsByStage;
    id dependencies = nil,
       dependents = nil;

    @autoreleasepool {
        /*	Iterate over all stages, getting dependency and dependent sets.
                This is done in advance so that -dependencies and -dependents may
                register stages.
        */
        for (;;) {
            /*	Loop while there are stages whose dependency lists haven't been
                    checked. This is an indeterminate loop since new ones can be
                    added.
            */
            if (_waitingStages.empty())
                break;
            const oo::ObjCRef<OOOXPVerifierStage*> waiting = _waitingStages.front();
            _waitingStages.erase(_waitingStages.begin());
            stage = waiting.get();

            dependencies = [stage dependencies];
            if (dependencies != nil) {
                dependenciesByStage[stage] = oo::StringsFrom(dependencies);
            }

            dependents = [stage dependents];
            if (dependents != nil) {
                dependentsByStage[stage] = oo::StringsFrom(dependents);
            }
        }
        _waitingStages.clear();
        _openForRegistration = NO;

        // Iterate over all stages, resolving dependencies.
        std::vector<std::string> stageKeys; // Get the keys up front because we may need to remove entries from the map.
        for (const auto& entry : _stagesByName)
            stageKeys.push_back(entry.first);

        for (const std::string& stageKey : stageKeys) {
            const auto found = _stagesByName.find(stageKey);
            if (found == _stagesByName.end())
                continue;
            stage = found->second.get();

            // Sanity check
            name = [stage name];
            if (!oo::IsNSString(name) || oo::StdString(name) != stageKey) {
                OOLog(@"verifyOXP.buildDependencyGraph.badName", @"***** Stage name appears to have changed from \"%@\" to \"%@\" for verifier stage %@, removing.", oo::NSStringFrom(stageKey), name, stage);
                _stagesByName.erase(stageKey);
                continue;
            }

            // Get dependency set
            const auto stageDependencies = dependenciesByStage.find(stage);

            if (stageDependencies != dependenciesByStage.end() && ![self setUpDependencies:stageDependencies->second forStage:stage]) {
                _stagesByName.erase(stageKey);
            }
        }

        /*	Iterate over all stages again, resolving reverse dependencies.
                This is done in a separate pass because reverse dependencies are "weak"
                while forward dependencies are "strong".
        */
        stageKeys.clear();
        for (const auto& entry : _stagesByName)
            stageKeys.push_back(entry.first);

        for (const std::string& stageKey : stageKeys) {
            const auto found = _stagesByName.find(stageKey);
            if (found == _stagesByName.end())
                continue;
            stage = found->second.get();

            // Get dependent set
            const auto stageDependents = dependentsByStage.find(stage);

            if (stageDependents != dependentsByStage.end()) {
                [self setUpDependents:stageDependents->second forStage:stage];
            }
        }

        for (const auto& entry : _stagesByName)
            _waitingStages.push_back(entry.second);
        for (const auto& waiting : _waitingStages)
            [waiting.get() dependencyRegistrationComplete];

        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"oxp-verifier-dump-debug-graphviz"]) {
            [self dumpDebugGraphviz];
        }
    }
}

- (void)runStages
{
    void* pool = NULL;
    OOOXPVerifierStage* stageToRun = nil;
    id stageName = nil;

    // Loop while there are still stages to run.
    for (;;) {
        pool = objc_autoreleasePoolPush();

        // Look through queue for a stage that's ready
        stageToRun = nil;
        for (const auto& candidateStage : _waitingStages) {
            if ([candidateStage.get() canRun]) {
                stageToRun = candidateStage.get();
                break;
            }
        }
        if (stageToRun == nil) {
            // No more runnable stages
            objc_autoreleasePoolPop(pool);
            break;
        }

        stageName = nil;
        OOLogPushIndent();
        @try {
            stageName = [stageToRun name];
            if ([stageToRun shouldRun]) {
                NoteVerificationStage(_displayName, oo::DescriptionOf(stageName)); // "%@" text, as the old format printed it
                OOLog(@"verifyOXP.runStage", @"%@", stageName);
                OOLogIndent();
                [stageToRun performRun];
            } else {
                OOLog(@"verifyOXP.verbose.skipStage", @"- Skipping stage: %@ (nothing to do).", stageName);
                [stageToRun noteSkipped];
            }
        }
        @catch (NSException* exception) {
            if (stageName == nil)
                stageName = [[stageToRun class] description];
            OOLog(@"verifyOXP.exception", @"***** Exception occurred when running OXP verifier stage \"%@\": %@: %@", stageName, [exception name], [exception reason]);
        }
        OOLogPopIndent();

        std::erase(_waitingStages, stageToRun);
        objc_autoreleasePoolPop(pool);
    }

    pool = objc_autoreleasePoolPush();

    if (!_waitingStages.empty()) {
        OOLog(@"verifyOXP.incomplete", @"%@", @"Some verifier stages could not be run:");
        OOLogIndent();
        for (const auto& candidateStage : _waitingStages) {
            OOLog(@"verifyOXP.incomplete.item", @"%@", candidateStage.get());
        }
        OOLogOutdent();
    }
    _waitingStages.clear();

    objc_autoreleasePoolPop(pool);
}

- (BOOL)setUpDependencies:(const std::vector<std::string>&)dependencies
                 forStage:(OOOXPVerifierStage*)stage
{
    OOOXPVerifierStage* depStage = nil;

    // Iterate over dependencies, connecting them up.
    for (const std::string& depName : dependencies) {
        depStage = [self cxx_stageWithName:depName];
        if (depStage == nil) {
            OOLog(@"verifyOXP.buildDependencyGraph.unresolved", @"Verifier stage %@ has unresolved dependency \"%@\", skipping.", stage, oo::NSStringFrom(depName));
            return NO;
        }

        if ([depStage isDependentOf:stage]) {
            OOLog(@"verifyOXP.buildDependencyGraph.circularReference", @"Verifier stages %@ and %@ have a dependency loop, skipping.", stage, depStage);
            _stagesByName.erase(depName);
            return NO;
        }

        [stage registerDependency:depStage];
    }

    return YES;
}

- (void)setUpDependents:(const std::vector<std::string>&)dependents
               forStage:(OOOXPVerifierStage*)stage
{
    OOOXPVerifierStage* depStage = nil;

    // Iterate over dependents, connecting them up.
    for (const std::string& depName : dependents) {
        depStage = [self cxx_stageWithName:depName];
        if (depStage == nil) {
            OOLog(@"verifyOXP.buildDependencyGraph.unresolved", @"Verifier stage %@ has unresolved dependent \"%@\".", stage, oo::NSStringFrom(depName));
            continue; // Unresolved/conflicting dependents are non-fatal
        }

        if ([stage isDependentOf:depStage]) {
            OOLog(@"verifyOXP.buildDependencyGraph.circularReference", @"Verifier stage %@ lists %@ as both dependent and dependency (possibly indirectly); will execute %@ after %@.", stage, depStage, stage, depStage);
            continue;
        }

        [depStage registerDependency:stage];
    }
}

- (void)dumpDebugGraphviz
{
    using oo::str::FormatArg;

    // The templates are data (verifyOXP.plist), so they are formatted at run time (ADR-0043 item 19).
    const oo::PList graphVizTemplate = [self cxx_configurationDictionaryForKey:"debugGraphvizTempate"];
    std::string graphViz = oo::str::formatRuntime(graphVizTemplate.get<std::string>("preamble"), { oo::date::description() });

    /*	Pass 1: enumerate over graph setting node attributes for each stage.
            We use pointers as node names for simplicity of generation.
    */
    std::string arcTemplate = graphVizTemplate.get<std::string>("node");
    for (const auto& entry : _stagesByName) {
        OOOXPVerifierStage* stage = entry.second.get();
        graphViz += oo::str::formatRuntime(arcTemplate, { FormatArg::pointer(stage), oo::DescriptionOf([stage class]), oo::DescriptionOf([stage name]) });
    }

    graphViz += graphVizTemplate.get<std::string>("forwardPreamble");

    /*	Pass 2: enumerate over graph setting forward arcs for each dependency.
     */
    arcTemplate = graphVizTemplate.get<std::string>("forwardArc");
    const std::string startTemplate = graphVizTemplate.get<std::string>("startArc");
    for (const auto& entry : _stagesByName) {
        OOOXPVerifierStage* stage = entry.second.get();
        const std::vector<oo::ObjCRef<OOOXPVerifierStage*>> deps = [stage resolvedDependencies];
        if (!deps.empty()) {
            for (const auto& dep : deps) {
                graphViz += oo::str::formatRuntime(arcTemplate, { FormatArg::pointer(dep.get()), FormatArg::pointer(stage) });
            }
        } else {
            graphViz += oo::str::formatRuntime(startTemplate, { FormatArg::pointer(stage) });
        }
    }

    graphViz += graphVizTemplate.get<std::string>("backwardPreamble");

    /*	Pass 3: enumerate over graph setting backward arcs for each dependent.
     */
    arcTemplate = graphVizTemplate.get<std::string>("backwardArc");
    const std::string endTemplate = graphVizTemplate.get<std::string>("endArc");
    for (const auto& entry : _stagesByName) {
        OOOXPVerifierStage* stage = entry.second.get();
        const std::vector<oo::ObjCRef<OOOXPVerifierStage*>> deps = [stage resolvedDependents];
        if (!deps.empty()) {
            for (const auto& dep : deps) {
                graphViz += oo::str::formatRuntime(arcTemplate, { FormatArg::pointer(dep.get()), FormatArg::pointer(stage) });
            }
        } else {
            graphViz += oo::str::formatRuntime(endTemplate, { FormatArg::pointer(stage) });
        }
    }

    graphViz += graphVizTemplate.get<std::string>("postamble");

    // Write file: what +[ResourceManager writeDiagnosticString:toFileNamed:] did for a name with no
    // directory part (UTF-8, atomically, in the diagnostic directory).
    const std::optional<std::string> directory = [ResourceManager cxx_diagnosticFileLocation];
    if (directory.has_value()) {
        const std::string path = oo::str::appendingPathComponent(*directory, "OXPVerifierStageDependencies.dot");
        (void)oo::fs::writeFile(oo::fs::pathFromUTF8(path), oo::Data::fromString(graphViz));
    }
}

@end

#import "OOLogOutputHandler.h"

namespace {

void SwitchLogFile(const std::string& name)
{
    // #ifndef OOLITE_LINUX
    //  -stringByAppendingPathExtension: has no oo::str form yet: it runs on the bridged string.
    const std::string logName = oo::StdString([oo::NSStringFrom(name) stringByAppendingPathExtension:@"log"]);
    OOLog(@"verifyOXP.switchingLog", @"Switching log files -- logging to \"%@\".", oo::NSStringFrom(logName));
    OOLogOutputHandlerChangeLogFile(oo::NSStringFrom(logName));
    // #else
    //	OOLog(@"verifyOXP.switchingLog", @"Switching logging to <stdout>.");
    //	OOLogOutputHandlerStartLoggingToStdout();
    // #endif
}

void NoteVerificationStage(const std::string& displayName, const std::string& stage)
{
    [[GameController sharedController] logProgress:oo::NSStringFrom(oo::str::format("Verifying %s\n%s", displayName.c_str(), stage.c_str()))];
}

void OpenLogFile()
{
    //	Open log file in appropriate application / provide feedback.

    if (oo::PListView([NSUserDefaults standardUserDefaults]).get<bool>(@"oxp-verifier-open-log", YES)) {
#if OOLITE_MAC_COCOA_UI
        [[NSWorkspace sharedWorkspace] openFile:OOLogHandlerGetLogPath()];
#elif OOLITE_WINDOWS
        // ShellExecute will automatically use the app associated with .log files
        ShellExecute(NULL, NULL, [OOLogHandlerGetLogPath() UTF8String], NULL, NULL, SW_SHOWNORMAL);
#elif OOLITE_LINUX
        // MKW - needed to suppress 'ignoring return value' warning for system() call
        //		int ret;
        // CIM - and now the compiler complains about that too... casting return
        // value to void seems to keep it quiet for now
        // Nothing to do here, since we dump to stdout instead of to a file.
        // OOLogOutputHandlerStopLoggingToStdout();
        (void)system(oo::str::format("cat \"%s\"", oo::DescriptionOf(OOLogHandlerGetLogPath()).c_str()).c_str());
#else
        do {
        } while (0);
#endif
    }
}

} // namespace

#endif // OO_OXP_VERIFIER_ENABLED
