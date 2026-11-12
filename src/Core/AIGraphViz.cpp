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

#include <format>
#include <string_view>

#include "OOStringParsing.h"
#include "ResourceManager.h"
#include "oofnd/String.hpp"

/*	The state machine is an oo::PList and the dump is built as a
   std::string. States and handlers are visited in key order (byte order), and
   the special nodes are written in sorted order; the .dot text is a debug dump.
*/
namespace {

using HandlerKeys = std::map<std::string, std::map<std::string, std::string>>;

// A command string, where the Foundation code read nil for anything else:
// nullopt when the element is missing or neither a string nor a number.
std::optional<std::string> CommandAt(const oo::PList* handlerCommands,
                                     std::size_t index) {
  const oo::PList* value =
      (handlerCommands != nullptr) ? handlerCommands->at(index) : nullptr;
  if (value == nullptr || !(value->isString() || value->isNumber()))
    return std::nullopt;
  return handlerCommands->at<std::string>(index);
}

// Generate and track unique identifiers for state-handler pairs.
std::string HandlerToken(const std::string& state, const std::string& handler,
                         HandlerKeys& handlerKeys,
                         std::set<std::string>& uniqueSet) {
  std::map<std::string, std::string>& stateDict = handlerKeys[state];
  const auto found = stateDict.find(handler);
  if (found != stateDict.end()) return found->second;

  std::string result = std::format("{}_h_{}", state, handler);
  result = cxx_GraphVizTokenString(result, &uniqueSet);

  stateDict[handler] = result;

  return result;
}

void AddSimpleSpecialNodeLink(std::string& graphViz,
                              const std::string& handlerToken,
                              const std::string& name, std::string_view shape,
                              std::string_view color,
                              std::set<std::string>& specialNodes) {
  std::string identifier = cxx_GraphVizTokenString("special_" + name, nullptr);
  std::string declaration =
      std::format("\t{} [label=\"{}\" color=\"#{}\" shape={}]\n", identifier,
                  cxx_EscapedGraphVizString(name), color, shape);
  specialNodes.insert(declaration);

  graphViz += std::format("\t{} -> {} [color=\"#{}\"]\n", handlerToken,
                          identifier, color);
}

void AddExitAINode(std::string& graphViz, const std::string& handlerToken,
                   const std::optional<std::string>& message,
                   std::set<std::string>& specialNodes) {
  std::string token;
  std::string label;
  if (!message.has_value() || *message == "RESTARTED" || message->empty()) {
    token = "exitAI";
    label = "exitAI";
  } else {
    token = cxx_GraphVizTokenString("exitAI_" + *message, nullptr);
    label = cxx_EscapedGraphVizString("exitAIWithMessage:\n" + *message);
  }

  specialNodes.insert(std::format(
      "\t{} [label=\"{}\" color=\"#0000A0\" shape=ellipse]\n", token, label));
  graphViz +=
      std::format("\t{} -> {} [color=\"#0000C0\"]\n", handlerToken, token);
}

void AddChangeAINode(std::string& graphViz, const std::string& handlerToken,
                     const std::string& method,
                     const std::vector<std::string>& components,
                     const oo::PList* handlerCommands, std::size_t commandIter,
                     std::size_t commandCount,
                     std::set<std::string>& specialNodes) {
  std::string methodTag = method.substr(0, method.size() - 3);  // delete "To:".

  if (components.size() > 1) {
    const std::string& targetAI = components[1];
    std::string token = std::format("{}_{}", methodTag, targetAI);
    std::string label = std::format("{}\n{}", method, targetAI);

    // Look through remaining commands for a setStateTo:, which applies to the
    // new AI.
    std::optional<std::string> targetState;
    std::size_t j = commandIter;
    for (; j < commandCount; j++) {
      const std::optional<std::string> command = CommandAt(handlerCommands, j);
      if (command.has_value() && oo::str::hasPrefix(*command, "setStateTo:")) {
        const std::vector<std::string> stateComponents =
            oo::str::tokens(*command);
        if (stateComponents.size() > 1) targetState = stateComponents[1];
      }
    }
    if (targetState.has_value()) {
      token = std::format("{}_{}", token, *targetState);
      label = std::format("{} ({})", label, *targetState);
    }

    token = cxx_GraphVizTokenString(token, nullptr);
    label = cxx_EscapedGraphVizString(label);

    specialNodes.insert(std::format(
        "\t{} [label=\"{}\" color=\"#408000\" shape=ellipse]\n", token, label));
    graphViz +=
        std::format("\t{} -> {} [color=\"#408000\"]\n", handlerToken, token);
  } else {
    specialNodes.insert(std::format(
        "\tspecial_broken_{} [label=\"Broken {} command!\\n(No target AI "
        "specified.)\" color=\"#C00000\" shape=diamond]\n",
        methodTag, method));
    graphViz += std::format("\t{} -> tspecial_broken_{} [color=\"#C00000\"]\n",
                            handlerToken, methodTag);
  }
}

void HandleOneCommand(std::string& graphViz, const std::string& stateKey,
                      const std::string& handlerKey, HandlerKeys& handlerKeys,
                      const oo::PList* handlerCommands, std::size_t commandIter,
                      std::size_t commandCount,
                      std::set<std::string>& specialNodes,
                      std::set<std::string>& uniqueSet,
                      bool* haveSetOrSwichAI) {
  const std::optional<std::string> command =
      CommandAt(handlerCommands, commandIter);
  if (EXPECT_NOT(!command.has_value())) return;

  const std::vector<std::string> components = oo::str::tokens(*command);
  // (an empty command has no method: -objectAtIndex:0 raised there)
  if (EXPECT_NOT(components.empty())) return;
  const std::string& method = components[0];
  std::string handlerToken =
      HandlerToken(stateKey, handlerKey, handlerKeys, uniqueSet);

  if (!*haveSetOrSwichAI && method == "setStateTo:") {
    if (components.size() > 1) {
      const std::string& targetState = components[1];
      std::string targetLabel =
          HandlerToken(targetState, "ENTER", handlerKeys, uniqueSet);
      bool constraint = true;
      if (targetState == stateKey || targetState == "GLOBAL")
        constraint = false;

      graphViz += std::format("\t{} -> {} [lhead=cluster_{}{}]\n", handlerToken,
                              targetLabel, targetState,
                              constraint ? "" : " constraint=false");
    } else {
      specialNodes.insert(
          "\tspecial_brokenSetStateTo [label=\"Broken setStateTo: "
          "command!\\n(No target state specified.)\" color=\"#C00000\" "
          "shape=diamond]\n");
      graphViz +=
          std::format("\t{} -> special_brokenSetStateTo [color=\"#C00000\"]\n",
                      handlerToken);
    }
  } else if (method == "becomeExplosion") {
    AddSimpleSpecialNodeLink(graphViz, handlerToken, "becomeExplosion",
                             "diamond", "804000", specialNodes);
  } else if (method == "becomeEnergyBlast") {
    AddSimpleSpecialNodeLink(graphViz, handlerToken, "becomeEnergyBlast",
                             "diamond", "804000", specialNodes);
  } else if (method == "landOnPlanet") {
    AddSimpleSpecialNodeLink(graphViz, handlerToken, "landOnPlanet", "diamond",
                             "008040", specialNodes);
  } else if (method == "performHyperSpaceExit") {
    AddSimpleSpecialNodeLink(graphViz, handlerToken, "performHyperSpaceExit",
                             "box", "008080", specialNodes);
  } else if (method == "performHyperSpaceExitWithoutReplacing") {
    AddSimpleSpecialNodeLink(graphViz, handlerToken,
                             "performHyperSpaceExitWithoutReplacing", "box",
                             "008080", specialNodes);
  } else if (method == "enterTargetWormhole") {
    AddSimpleSpecialNodeLink(graphViz, handlerToken, "enterTargetWormhole",
                             "box", "008080", specialNodes);
  } else if (method == "becomeUncontrolledThargon") {
    AddSimpleSpecialNodeLink(graphViz, handlerToken,
                             "becomeUncontrolledThargon", "ellipse", "804000",
                             specialNodes);
  } else if (method == "exitAIWithMessage:") {
    const std::optional<std::string> message =
        (components.size() > 1) ? std::optional<std::string>(components[1])
                                : std::nullopt;
    AddExitAINode(graphViz, handlerToken, message, specialNodes);
  } else if (method == "setAITo:" || method == "switchAITo:") {
    *haveSetOrSwichAI = true;
    AddChangeAINode(graphViz, handlerToken, method, components, handlerCommands,
                    commandIter, commandCount, specialNodes);
  }
}

}  // namespace

void GenerateGraphVizForAIStateMachine(const oo::PList& stateMachine,
                                       const std::string& smName) {
  std::set<std::string> uniqueSet;
  HandlerKeys handlerKeys;

  std::string graphViz = std::format(
      "digraph ai_flow\n{{\n\tgraph [charset=\"UTF-8\", label=\"{} transition "
      "diagram\", labelloc=t, labeljust=l rankdir=LR compound=true nodesep=0.1 "
      "ranksep=2.5 fontname=Helvetica]\n\tedge [arrowhead=normal]\n\tnode "
      "[shape=box height=0.2 width=3.5 fontname=Helvetica "
      "color=\"#808080\"]\n\t\n\tspecial_start [shape=ellipse "
      "color=\"#0000C0\" label=\"Start\"]\n\tspecial_start -> {} "
      "[lhead=\"cluster_GLOBAL\" color=\"#0000A0\"]\n",
      cxx_EscapedGraphVizString(smName),
      HandlerToken("GLOBAL", "ENTER", handlerKeys, uniqueSet));

  std::set<std::string> specialNodes;

  if (const oo::PList::Dict* states = stateMachine.getIf<oo::PList::Dict>()) {
    for (const auto& [stateKey, stateValue] : *states) {
      // Nothing here autoreleases, so there is no pool per state; the scope
      // below is what the pool's lifetime was.
      {
        graphViz +=
            std::format("\t\n\tsubgraph cluster_{}\n\t{{\n\t\tlabel=\"{}\"\n",
                        stateKey, cxx_EscapedGraphVizString(stateKey));

        const oo::PList::Dict* state = stateValue.getIf<oo::PList::Dict>();
        if (state != nullptr) {
          for (const auto& [handlerKey, handlerValue] : *state) {
            graphViz += std::format(
                "\t\t{} [label=\"{}\"]\n",
                HandlerToken(stateKey, handlerKey, handlerKeys, uniqueSet),
                cxx_EscapedGraphVizString(handlerKey));
          }
        }

        // Ensure there is an ENTER handler for arrows to point at.
        if (state == nullptr || state->find("ENTER") == state->end()) {
          graphViz += std::format(
              "\t\t{} [label=\"ENTER (implicit)\"] // No ENTER handler in "
              "file, but it's still the target of any incoming transitions.\n",
              HandlerToken(stateKey, "ENTER", handlerKeys, uniqueSet));
        }

        graphViz += "\t}\n";

        // Go through each handler looking for interesting methods.
        if (state != nullptr) {
          for (const auto& [handlerKey, handlerValue] : *state) {
            const oo::PList* handlerCommands =
                handlerValue.isArray() ? &handlerValue : nullptr;
            std::size_t commandIter,
                commandCount =
                    (handlerCommands != nullptr) ? handlerCommands->count() : 0;
            bool haveSetOrSwichAI = false;

            for (commandIter = 0; commandIter < commandCount; commandIter++) {
              HandleOneCommand(graphViz, stateKey, handlerKey, handlerKeys,
                               handlerCommands, commandIter, commandCount,
                               specialNodes, uniqueSet, &haveSetOrSwichAI);
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
  ResourceManager::writeDiagnosticString(
      graphViz, std::format("AI Dumps/{}.dot", smName));
}

#endif
