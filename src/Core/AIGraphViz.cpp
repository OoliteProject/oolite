/*

AIGraphViz.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#if DEBUG_GRAPHVIZ

#include "AIGraphViz.h"
#include "OOStringParsing.h"
#include "ResourceManager.h"
#include "oofnd/String.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-ndxe): the state machine is an oo::PList and the
        dump is built as a std::string. States and handlers are visited in key order (byte order; they
        were in the dictionaries' hash order), and the special nodes are written in sorted order (they
        were in the set's hash order); the .dot text is a debug dump, not a golden.
*/
namespace {

using HandlerKeys = std::map<std::string, std::map<std::string, std::string>>;

// A command string, where the Foundation code read nil for anything else: nullopt when the
// element is missing or neither a string nor a number.
std::optional<std::string> CommandAt(const oo::PList* handlerCommands, std::size_t index)
{
    const oo::PList* value = (handlerCommands != nullptr) ? handlerCommands->at(index) : nullptr;
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return handlerCommands->at<std::string>(index);
}

// Generate and track unique identifiers for state-handler pairs.
std::string HandlerToken(const std::string& state, const std::string& handler, HandlerKeys& handlerKeys, std::set<std::string>& uniqueSet)
{
    std::map<std::string, std::string>& stateDict = handlerKeys[state];
    const auto found = stateDict.find(handler);
    if (found != stateDict.end())
        return found->second;

    std::string result = oo::str::format("%s_h_%s", state.c_str(), handler.c_str());
    result = cxx_GraphVizTokenString(result, &uniqueSet);

    stateDict[handler] = result;

    return result;
}

void AddSimpleSpecialNodeLink(std::string& graphViz, const std::string& handlerToken, const std::string& name, const char* shape, const char* color, std::set<std::string>& specialNodes)
{
    std::string identifier = cxx_GraphVizTokenString("special_" + name, nullptr);
    std::string declaration = oo::str::format("\t%s [label=\"%s\" color=\"#%s\" shape=%s]\n", identifier.c_str(), cxx_EscapedGraphVizString(name).c_str(), color, shape);
    specialNodes.insert(declaration);

    graphViz += oo::str::format("\t%s -> %s [color=\"#%s\"]\n", handlerToken.c_str(), identifier.c_str(), color);
}

void AddExitAINode(std::string& graphViz, const std::string& handlerToken, const std::optional<std::string>& message, std::set<std::string>& specialNodes)
{
    std::string token;
    std::string label;
    if (!message.has_value() || *message == "RESTARTED" || message->empty()) {
        token = "exitAI";
        label = "exitAI";
    } else {
        token = cxx_GraphVizTokenString("exitAI_" + *message, nullptr);
        label = cxx_EscapedGraphVizString("exitAIWithMessage:\n" + *message);
    }

    specialNodes.insert(oo::str::format("\t%s [label=\"%s\" color=\"#0000A0\" shape=ellipse]\n", token.c_str(), label.c_str()));
    graphViz += oo::str::format("\t%s -> %s [color=\"#0000C0\"]\n", handlerToken.c_str(), token.c_str());
}

void AddChangeAINode(std::string& graphViz, const std::string& handlerToken, const std::string& method, const std::vector<std::string>& components, const oo::PList* handlerCommands, std::size_t commandIter, std::size_t commandCount, std::set<std::string>& specialNodes)
{
    std::string methodTag = method.substr(0, method.size() - 3); // delete "To:".

    if (components.size() > 1) {
        const std::string& targetAI = components[1];
        std::string token = oo::str::format("%s_%s", methodTag.c_str(), targetAI.c_str());
        std::string label = oo::str::format("%s\n%s", method.c_str(), targetAI.c_str());

        // Look through remaining commands for a setStateTo:, which applies to the new AI.
        std::optional<std::string> targetState;
        std::size_t j = commandIter;
        for (; j < commandCount; j++) {
            const std::optional<std::string> command = CommandAt(handlerCommands, j);
            if (command.has_value() && oo::str::hasPrefix(*command, "setStateTo:")) {
                const std::vector<std::string> stateComponents = oo::str::tokens(*command);
                if (stateComponents.size() > 1)
                    targetState = stateComponents[1];
            }
        }
        if (targetState.has_value()) {
            token = oo::str::format("%s_%s", token.c_str(), targetState->c_str());
            label = oo::str::format("%s (%s)", label.c_str(), targetState->c_str());
        }

        token = cxx_GraphVizTokenString(token, nullptr);
        label = cxx_EscapedGraphVizString(label);

        specialNodes.insert(oo::str::format("\t%s [label=\"%s\" color=\"#408000\" shape=ellipse]\n", token.c_str(), label.c_str()));
        graphViz += oo::str::format("\t%s -> %s [color=\"#408000\"]\n", handlerToken.c_str(), token.c_str());
    } else {
        specialNodes.insert(oo::str::format("\tspecial_broken_%s [label=\"Broken %s command!\\n(No target AI specified.)\" color=\"#C00000\" shape=diamond]\n", methodTag.c_str(), method.c_str()));
        graphViz += oo::str::format("\t%s -> tspecial_broken_%s [color=\"#C00000\"]\n", handlerToken.c_str(), methodTag.c_str());
    }
}

void HandleOneCommand(std::string& graphViz, const std::string& stateKey, const std::string& handlerKey, HandlerKeys& handlerKeys, const oo::PList* handlerCommands, std::size_t commandIter, std::size_t commandCount, std::set<std::string>& specialNodes, std::set<std::string>& uniqueSet, BOOL* haveSetOrSwichAI)
{
    const std::optional<std::string> command = CommandAt(handlerCommands, commandIter);
    if (EXPECT_NOT(!command.has_value()))
        return;

    const std::vector<std::string> components = oo::str::tokens(*command);
    // (an empty command has no method: -objectAtIndex:0 raised there)
    if (EXPECT_NOT(components.empty()))
        return;
    const std::string& method = components[0];
    std::string handlerToken = HandlerToken(stateKey, handlerKey, handlerKeys, uniqueSet);

    if (!*haveSetOrSwichAI && method == "setStateTo:") {
        if (components.size() > 1) {
            const std::string& targetState = components[1];
            std::string targetLabel = HandlerToken(targetState, "ENTER", handlerKeys, uniqueSet);
            BOOL constraint = YES;
            if (targetState == stateKey || targetState == "GLOBAL")
                constraint = NO;

            graphViz += oo::str::format("\t%s -> %s [lhead=cluster_%s%s]\n", handlerToken.c_str(), targetLabel.c_str(), targetState.c_str(), constraint ? "" : " constraint=false");
        } else {
            specialNodes.insert("\tspecial_brokenSetStateTo [label=\"Broken setStateTo: command!\\n(No target state specified.)\" color=\"#C00000\" shape=diamond]\n");
            graphViz += oo::str::format("\t%s -> special_brokenSetStateTo [color=\"#C00000\"]\n", handlerToken.c_str());
        }
    } else if (method == "becomeExplosion") {
        AddSimpleSpecialNodeLink(graphViz, handlerToken, "becomeExplosion", "diamond", "804000", specialNodes);
    } else if (method == "becomeEnergyBlast") {
        AddSimpleSpecialNodeLink(graphViz, handlerToken, "becomeEnergyBlast", "diamond", "804000", specialNodes);
    } else if (method == "landOnPlanet") {
        AddSimpleSpecialNodeLink(graphViz, handlerToken, "landOnPlanet", "diamond", "008040", specialNodes);
    } else if (method == "performHyperSpaceExit") {
        AddSimpleSpecialNodeLink(graphViz, handlerToken, "performHyperSpaceExit", "box", "008080", specialNodes);
    } else if (method == "performHyperSpaceExitWithoutReplacing") {
        AddSimpleSpecialNodeLink(graphViz, handlerToken, "performHyperSpaceExitWithoutReplacing", "box", "008080", specialNodes);
    } else if (method == "enterTargetWormhole") {
        AddSimpleSpecialNodeLink(graphViz, handlerToken, "enterTargetWormhole", "box", "008080", specialNodes);
    } else if (method == "becomeUncontrolledThargon") {
        AddSimpleSpecialNodeLink(graphViz, handlerToken, "becomeUncontrolledThargon", "ellipse", "804000", specialNodes);
    } else if (method == "exitAIWithMessage:") {
        const std::optional<std::string> message = (components.size() > 1) ? std::optional<std::string>(components[1]) : std::nullopt;
        AddExitAINode(graphViz, handlerToken, message, specialNodes);
    } else if (method == "setAITo:" || method == "switchAITo:") {
        *haveSetOrSwichAI = YES;
        AddChangeAINode(graphViz, handlerToken, method, components, handlerCommands, commandIter, commandCount, specialNodes);
    }
}

} // namespace

void GenerateGraphVizForAIStateMachine(const oo::PList& stateMachine, const std::string& smName)
{
    std::set<std::string> uniqueSet;
    HandlerKeys handlerKeys;

    std::string graphViz = oo::str::format(
        "digraph ai_flow\n{\n"
        "\tgraph [charset=\"UTF-8\", label=\"%s transition diagram\", labelloc=t, labeljust=l rankdir=LR compound=true nodesep=0.1 ranksep=2.5 fontname=Helvetica]\n"
        "\tedge [arrowhead=normal]\n"
        "\tnode [shape=box height=0.2 width=3.5 fontname=Helvetica color=\"#808080\"]\n\t\n"
        "\tspecial_start [shape=ellipse color=\"#0000C0\" label=\"Start\"]\n\tspecial_start -> %s [lhead=\"cluster_GLOBAL\" color=\"#0000A0\"]\n",
        cxx_EscapedGraphVizString(smName).c_str(), HandlerToken("GLOBAL", "ENTER", handlerKeys, uniqueSet).c_str());

    std::set<std::string> specialNodes;

    if (const oo::PList::Dict* states = stateMachine.getIf<oo::PList::Dict>()) {
        for (const auto& [stateKey, stateValue] : *states) {
            // Was an autorelease pool per state; since the Foundation sweep nothing here autoreleases
            // (Phase 3 recipe: the pool becomes the end of the scope; bead oo-5q8h).
            {
                graphViz += oo::str::format("\t\n\tsubgraph cluster_%s\n\t{\n\t\tlabel=\"%s\"\n", stateKey.c_str(), cxx_EscapedGraphVizString(stateKey).c_str());

                const oo::PList::Dict* state = stateValue.getIf<oo::PList::Dict>();
                if (state != nullptr) {
                    for (const auto& [handlerKey, handlerValue] : *state) {
                        graphViz += oo::str::format("\t\t%s [label=\"%s\"]\n", HandlerToken(stateKey, handlerKey, handlerKeys, uniqueSet).c_str(), cxx_EscapedGraphVizString(handlerKey).c_str());
                    }
                }

                // Ensure there is an ENTER handler for arrows to point at.
                if (state == nullptr || state->find("ENTER") == state->end()) {
                    graphViz += oo::str::format("\t\t%s [label=\"ENTER (implicit)\"] // No ENTER handler in file, but it's still the target of any incoming transitions.\n", HandlerToken(stateKey, "ENTER", handlerKeys, uniqueSet).c_str());
                }

                graphViz += "\t}\n";

                // Go through each handler looking for interesting methods.
                if (state != nullptr) {
                    for (const auto& [handlerKey, handlerValue] : *state) {
                        const oo::PList* handlerCommands = handlerValue.isArray() ? &handlerValue : nullptr;
                        std::size_t commandIter, commandCount = (handlerCommands != nullptr) ? handlerCommands->count() : 0;
                        BOOL haveSetOrSwichAI = NO;

                        for (commandIter = 0; commandIter < commandCount; commandIter++) {
                            HandleOneCommand(graphViz, stateKey, handlerKey, handlerKeys, handlerCommands, commandIter, commandCount, specialNodes, uniqueSet, &haveSetOrSwichAI);
                        }
                    }
                }
            }
        }
    }

    if (!specialNodes.empty()) {
        graphViz += "\t\n";

        for (const std::string& special : specialNodes) {
            graphViz += special;
        }
    }

    graphViz += "}\n";
    ResourceManager::writeDiagnosticString(graphViz, oo::str::format("AI Dumps/%s.dot", smName.c_str()));
}

#endif
