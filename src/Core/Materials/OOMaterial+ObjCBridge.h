/*

OOMaterial+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-smy): the Objective-C OOMaterial, a facade over the
C++ cxx::OOMaterial (OOMaterial.h), for the callers that message materials and for the materials
not converted yet (the three under OOBasicMaterial, whose facade derives from this one: bead
oo-vl43). Its interface is the one OOMaterial.h
declared before the conversion, copied exactly (same selectors, same types), so they compile and
behave unchanged. Imported as the last line of OOMaterial.h; do not import it directly.

It is a hierarchy root's facade, as OOOXPVerifierStage+ObjCBridge.h is (ADR-0056 Amendment 1):

        the material is                      its facade is                      virtual calls on the
                                                                                  C++ side reach
        -----------------------------------  ---------------------------------  ---------------------
        an Objective-C subclass              the subclass instance itself; its  the subclass's
          (unconverted, [[X alloc] init])    -init made its C++ part, an        methods (-doApply,
                                             adapter that forwards the virtual  -unapplyWithNext:,
                                             members to it                      -cxx_name, ...)
        a C++ subclass (converted)           made by oo::ToObjC, one live one   the C++ overrides
                                             per material (oo::ObjCPeers)

An Objective-C subclass's [super doApply] (and every other overridable method) reaches its nearest
converted superclass's own member (the adapter's super...() members), not the virtual one, so it
does what that class did. A C++ material's facade is the Objective-C class named after its C++
class, or after its nearest base class that has one (OOBasicMaterial for cxx::OOBasicMaterial).

        a caller that is                       holds / passes                   crosses with
        -------------------------------------  -------------------------------  -----------------------
        still Objective-C                      OOMaterial * (this facade)       nothing
        converted (C++), calling               cxx::OOMaterial * (borrowed)
          handing a material to Objective-C                                     oo::ToObjC(material)
          taking one from Objective-C                                           oo::ToCxx(objcMaterial)
        converted (C++), keeping one           oo::ObjCRef<OOMaterial *>        oo::ToObjC / oo::ToCxx
          while any subclass is Objective-C    (an Objective-C material's C++
                                               part does not retain it)

oo::ToObjC(oo::ToCxx(m)) == m for both kinds. Never add to this file; converted code does not
message the facade. Deleted by its deletion bead once every caller and every material is C++.


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

#ifndef OOMATERIAL_OBJCBRIDGE_H
#define OOMATERIAL_OBJCBRIDGE_H

@interface OOMaterial : OOObject {
@private
    oo::Ref<cxx::OOMaterial> _cxxMaterial;
}

// Called once at startup (by -[Universe init]).
+ (void)setUp;

- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.5)

// Make this the current material.
- (void)apply;

/*	Make no material the current material, tearing down anything set up by the
        current material.
*/
+ (void)applyNone;

/*	Get current material.
 */
+ (OOMaterial*)current;

/*	Ensure material is ready to be used in a display list. This is not
        required before using a material directly.
*/
- (void)ensureFinishedLoading;
- (BOOL)isFinishedLoading;

// Only used by shader material, but defined for all materials for convenience.
- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target;

// True if material wants three-component cube map texture coordinates.
- (BOOL)wantsNormalsAsTextureCoordinates;

#if OO_MULTITEXTURE
// Nasty hack: number of texture units for which the drawable should set its basic texture coordinates.
- (NSUInteger)countOfTextureUnitsWithBaseCoordinates;
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures;
#endif

@end

@interface OOMaterial (OOSubclassInterface)

// Subclass responsibilities - don't call directly.
- (BOOL)doApply; // Override instead of -apply
- (void)unapplyWithNext:(OOMaterial*)next;

// Call at top of dealloc
- (void)willDealloc;

@end

@interface OOMaterial (OOObjCBridge)

/*	The facade of a C++ material (oo::ToObjC makes it); or, from an initialiser of a converted
        intermediate class's facade (OOBasicMaterial, bead oo-vl43), an Objective-C material whose C++
        part is material, an oo::ObjCMaterial of that class (ADR-0056 amendment of bead oo-up4b, item
        2). Retains material.
*/
- (id)initWithCxxMaterial:(cxx::OOMaterial*)material;

/*	From a converted class's facade initialiser ([[OOBasicMaterial alloc] init...]): a new C++
        material, whose facade this is from now on (the peer oo::ToObjC answers).
*/
- (id)initWithNewCxxMaterial:(const oo::Ref<cxx::OOMaterial>&)material;

@end

namespace oo {

// The material's Objective-C object: an Objective-C material itself, else a C++ material's live
// facade (or a new one); autoreleased. nil for null.
OOMaterial* ToObjC(cxx::OOMaterial* material);
inline OOMaterial* ToObjC(const Ref<cxx::OOMaterial>& material) { return ToObjC(material.get()); }

// The C++ material behind an Objective-C one, borrowed (the Objective-C object retains it); null for nil.
cxx::OOMaterial* ToCxx(OOMaterial* material);

/*	The C++ part of an Objective-C material (an unconverted subclass), the adapter: each virtual
        member messages the Objective-C object, so the subclass's override runs, as it did when the
        base class was Objective-C. Base is the C++ class of its nearest converted superclass:
        cxx::OOMaterial when the root facade's -init makes it, cxx::OOBasicMaterial when that facade's
        initialisers do (ADR-0056 amendment of bead oo-up4b, item 1). The super...() members are Base's
        own, what [super ...] reached; the root facade answers with them when the subclass does not
        override a method, or calls super. The Objective-C object owns the adapter (its _cxxMaterial)
        and is not retained by it; its -dealloc clears the pointer, after which the members answer as a
        message to nil did.
*/
class ObjCMaterialLink {
public:
    ::OOMaterial* owner() { return _owner; }
    void ownerDeallocated() { _owner = nil; }

    virtual void superApply() = 0;
    virtual std::optional<std::string> superName() = 0;
    virtual std::optional<std::string> superDescriptionComponents() const = 0;
    virtual void superEnsureFinishedLoading() = 0;
    virtual bool superIsFinishedLoading() = 0;
    virtual void superSetBindingTarget(id<OOWeakReferenceSupport> target) = 0;
    virtual bool superWantsNormalsAsTextureCoordinates() = 0;
#if OO_MULTITEXTURE
    virtual NSUInteger superCountOfTextureUnitsWithBaseCoordinates() = 0;
#endif
#ifdef OO_DEBUG_MONITOR_ENABLED
    virtual std::vector<oo::ObjCRef<OOTexture*>> superAllTextures() = 0;
#endif
    virtual bool superDoApply() = 0;
    virtual void superUnapplyWithNext(cxx::OOMaterial* next) = 0;

protected:
    explicit ObjCMaterialLink(::OOMaterial* owner)
        : _owner(owner)
    {
    }
    ~ObjCMaterialLink() = default;

    ::OOMaterial* _owner = { }; // Not retained.
};

// Not final: an intermediate class's bridge derives from it for the members its class adds
// (OOBasicMaterial+ObjCBridge.mm's permitSpecular()).
template <class Base>
class ObjCMaterial : public Base, public ObjCMaterialLink {
public:
    explicit ObjCMaterial(::OOMaterial* owner)
        : ObjCMaterialLink(owner)
    {
    }

    void apply() override { [_owner apply]; }
    std::optional<std::string> name() override { return [_owner cxx_name]; }
    std::optional<std::string> descriptionComponents() const override { return [_owner cxx_descriptionComponents]; }
    void ensureFinishedLoading() override { [_owner ensureFinishedLoading]; }
    bool isFinishedLoading() override { return [_owner isFinishedLoading]; }
    void setBindingTarget(id<OOWeakReferenceSupport> target) override { [_owner setBindingTarget:target]; }
    bool wantsNormalsAsTextureCoordinates() override { return [_owner wantsNormalsAsTextureCoordinates]; }
#if OO_MULTITEXTURE
    NSUInteger countOfTextureUnitsWithBaseCoordinates() override { return [_owner countOfTextureUnitsWithBaseCoordinates]; }
#endif
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::vector<oo::ObjCRef<OOTexture*>> allTextures() override { return [_owner cxx_allTextures]; }
#endif
    bool doApply() override { return [_owner doApply]; }
    void unapplyWithNext(cxx::OOMaterial* next) override { [_owner unapplyWithNext:oo::ToObjC(next)]; }

    void superApply() override { Base::apply(); }
    std::optional<std::string> superName() override { return Base::name(); }
    std::optional<std::string> superDescriptionComponents() const override { return Base::descriptionComponents(); }
    void superEnsureFinishedLoading() override { Base::ensureFinishedLoading(); }
    bool superIsFinishedLoading() override { return Base::isFinishedLoading(); }
    void superSetBindingTarget(id<OOWeakReferenceSupport> target) override { Base::setBindingTarget(target); }
    bool superWantsNormalsAsTextureCoordinates() override { return Base::wantsNormalsAsTextureCoordinates(); }
#if OO_MULTITEXTURE
    NSUInteger superCountOfTextureUnitsWithBaseCoordinates() override { return Base::countOfTextureUnitsWithBaseCoordinates(); }
#endif
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::vector<oo::ObjCRef<OOTexture*>> superAllTextures() override { return Base::allTextures(); }
#endif
    bool superDoApply() override { return Base::doApply(); }
    void superUnapplyWithNext(cxx::OOMaterial* next) override { Base::unapplyWithNext(next); }
};

// The adapter, if material is an Objective-C material's C++ part; else null (a C++ material, or null).
ObjCMaterialLink* AsObjCMaterial(cxx::OOMaterial* material);

} // namespace oo

#endif // OOMATERIAL_OBJCBRIDGE_H
