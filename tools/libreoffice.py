#!/bin/python3
# This script controls LibreOffice
# inspired by https://stackoverflow.com/a/76600748/4222206

import uno
import sys
from ooodev.loader.lo import Lo
from ooodev.utils.info import Info
from com.sun.star.beans import XPropertySet
from com.sun.star.beans import XPropertyAccess

def main() -> int:
  print (sys.argv)
  
  with Lo.Loader(Lo.ConnectSocket(headless=True)) as loader:
    i = 0
    while i < len(sys.argv):
      arg = sys.argv[i]
      match arg:
        case "--load":
          i = i + 1
          docname = sys.argv[i]
          print ("loading " + docname)
          doc = Lo.open_doc(fnm=docname, loader=loader)
        case "--set":
          i=i+1
          val = sys.argv[i]
          items = val.split("=")
          name = items[0]
          value = items[1]
          print("setting " + name + "=>" + value)
          user_props = Info.get_user_defined_props(doc) # XPropertyContainer
          ps = Lo.qi(XPropertySet, user_props, True)
          
          try:
            ps.setPropertyValue(name, value)
          except:
            pa = Lo.qi(XPropertyAccess, user_props, True)
            names = []
            for propertyvalue in pa.getPropertyValues():
              names.append(propertyvalue.Name)
            print ("Cannot set property '" + name + "'. Known properties are ", names)
            return 1
        case "--save":
          i = i + 1
          docname = sys.argv[i]
          print ("saving " + docname)
          Lo.save_doc(doc=doc, fnm=docname)
        case _:
          print (i, sys.argv[i])
      i = i + 1
  return 0

if __name__ == "__main__":
    raise SystemExit(main())
