/*

OODataFromOXZFile.mm

OXZ-aware file reader.


Copyright (C) 2008-2013 Jens Ayton and contributors

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

#include "OOFoundation.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"
#include "unzip.h"

#define ZIP_BUFFER_SIZE 8192

std::optional<oo::Data> OODataFromOXZFile(const std::string& path) {
  const std::vector<std::string> components = oo::str::pathComponents(path);
  std::size_t i, cl = components.size();
  for (i = 0; i < cl; i++) {
    if (oo::str::lowercase(oo::str::pathExtension(components[i])) == "oxz") {
      break;
    }
  }
  // if i == cl then the path is entirely uncompressed
  if (i == cl) {
    const oo::fs::Path filePath = oo::fs::pathFromUTF8(path);
/* -initWithContentsOfMappedFile fails quietly under OS X if there's no file,
   but GNUstep complains. */
#if OOLITE_MAC_OS_X
    auto data = oo::fs::readFile(filePath);
    if (data) return std::move(*data);
    return std::nullopt;
#else
    const oo::fs::FileType type = oo::fs::fileType(filePath);

    if (type != oo::fs::FileType::none) {
      if (type != oo::fs::FileType::directory) {
        if (oo::fs::fileSize(filePath).value_or(0) == 0) {
          OO_LOG(cxx_kOOLogFileNotFound,
                 "Expected file but found empty file at {}", path);
        } else {
          auto data = oo::fs::readFile(filePath);
          if (data) return std::move(*data);
          return std::nullopt;
        }
      } else {
        OO_LOG(cxx_kOOLogFileNotFound,
               "Expected file but found directory at {}", path);
      }
    }
    return std::nullopt;
#endif
  }
  // otherwise components 0..i are the OXZ path, and i+1..n are the
  // path inside the OXZ
  const std::string zipFile =
      oo::str::pathWithComponents(std::vector<std::string>(
          components.begin(),
          components.begin() + static_cast<std::ptrdiff_t>(i) + 1));
  const std::string containedFile =
      oo::str::pathWithComponents(std::vector<std::string>(
          components.begin() + static_cast<std::ptrdiff_t>(i) + 1,
          components.end()));

  unzFile uf = NULL;
  const char* zipname = zipFile.c_str();
  if (zipname != NULL) {
    uf = unzOpen64(zipname);
  }
  if (uf == NULL) {
    // This is not necessarily an error - the OXZ manager tries to
    // do this as a test for the presence of managed OXZs
    //		OO_LOG(cxx_kOOLogFileNotFound, "Could not unzip OXZ at {}",
    // zipFile);
    return std::nullopt;
  }
  const char* filename = containedFile.c_str();
  // unzLocateFile(*, *, 1) = case-sensitive extract
  if (unzLocateFile(uf, filename, 1) != UNZ_OK) {
    unzClose(uf);
    /* Much of the time this function is called with the
     * expectation that the file may not necessarily exist -
     * e.g. on plist merges, config scans, etc. So don't add log
     * entries for this failure mode */
    //		OO_LOG(cxx_kOOLogFileNotFound, "Could not find {} within OXZ at
    //{}", containedFile, zipFile);
    return std::nullopt;
  }

  int err = UNZ_OK;
  unz_file_info64 file_info = {};
  err = unzGetCurrentFileInfo64(uf, &file_info, NULL, 0, NULL, 0, NULL, 0);
  if (err != UNZ_OK) {
    unzClose(uf);
    OO_LOG(cxx_kOOLogFileNotFound,
           "Could not get properties of {} within OXZ at {}", containedFile,
           zipFile);
    return std::nullopt;
  }

  err = unzOpenCurrentFile(uf);
  if (err != UNZ_OK) {
    unzClose(uf);
    OO_LOG(cxx_kOOLogFileNotFound, "Could not read {} within OXZ at {}",
           containedFile, zipFile);
    return std::nullopt;
  }

  oo::Data tmp;
  void* buf = (void*)malloc(ZIP_BUFFER_SIZE);
  do {
    err = unzReadCurrentFile(uf, buf, ZIP_BUFFER_SIZE);
    if (err < 0) {
      OO_LOG(cxx_kOOLogFileNotFound,
             "Could not read {} within OXZ at {} (err {})", containedFile,
             zipFile, err);
      break;
    }
    if (err == 0) {
      break;
    }
    tmp.append(buf, static_cast<std::size_t>(err));
  } while (err > 0);
  free(buf);

  err = unzCloseCurrentFile(uf);
  if (err != UNZ_OK) {
    unzClose(uf);
    OO_LOG(cxx_kOOLogFileNotFound, "Could not close {} within OXZ at {}",
           containedFile, zipFile);
    return std::nullopt;
  }

  unzClose(uf);
  return tmp;
}

bool OOOxzFileExistsAtPath(const std::string& path) {
  const std::vector<std::string> components = oo::str::pathComponents(path);
  std::size_t i, cl = components.size();
  for (i = 0; i < cl; i++) {
    if (oo::str::lowercase(oo::str::pathExtension(components[i])) == "oxz") {
      break;
    }
  }
  // if i == cl then the path is entirely uncompressed
  if (i == cl) {
    const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(path));
    if (type == oo::fs::FileType::directory) {
      return false;
    }
    return type != oo::fs::FileType::none;
  }

  const std::string zipFile =
      oo::str::pathWithComponents(std::vector<std::string>(
          components.begin(),
          components.begin() + static_cast<std::ptrdiff_t>(i) + 1));
  const std::string containedFile =
      oo::str::pathWithComponents(std::vector<std::string>(
          components.begin() + static_cast<std::ptrdiff_t>(i) + 1,
          components.end()));

  unzFile uf = unzOpen64(zipFile.c_str());
  if (uf == NULL) {
    return false;
  }
  bool result = true;
  if (unzLocateFile(uf, containedFile.c_str(), 1) != UNZ_OK) {
    result = false;
  } else {
    unz_file_info64 file_info = {};
    if (unzGetCurrentFileInfo64(uf, &file_info, NULL, 0, NULL, 0, NULL, 0) !=
        UNZ_OK) {
      result = false;
    }
  }
  unzClose(uf);
  return static_cast<bool>(result);
}
