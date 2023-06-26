include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(ci_cd_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(ci_cd_setup_options)
  option(ci_cd_ENABLE_HARDENING "Enable hardening" ON)
  option(ci_cd_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    ci_cd_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    ci_cd_ENABLE_HARDENING
    OFF)

  ci_cd_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR ci_cd_PACKAGING_MAINTAINER_MODE)
    option(ci_cd_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(ci_cd_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(ci_cd_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(ci_cd_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(ci_cd_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(ci_cd_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(ci_cd_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(ci_cd_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(ci_cd_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(ci_cd_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(ci_cd_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(ci_cd_ENABLE_PCH "Enable precompiled headers" OFF)
    option(ci_cd_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(ci_cd_ENABLE_IPO "Enable IPO/LTO" ON)
    option(ci_cd_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(ci_cd_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(ci_cd_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(ci_cd_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(ci_cd_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(ci_cd_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(ci_cd_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(ci_cd_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(ci_cd_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(ci_cd_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(ci_cd_ENABLE_PCH "Enable precompiled headers" OFF)
    option(ci_cd_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      ci_cd_ENABLE_IPO
      ci_cd_WARNINGS_AS_ERRORS
      ci_cd_ENABLE_USER_LINKER
      ci_cd_ENABLE_SANITIZER_ADDRESS
      ci_cd_ENABLE_SANITIZER_LEAK
      ci_cd_ENABLE_SANITIZER_UNDEFINED
      ci_cd_ENABLE_SANITIZER_THREAD
      ci_cd_ENABLE_SANITIZER_MEMORY
      ci_cd_ENABLE_UNITY_BUILD
      ci_cd_ENABLE_CLANG_TIDY
      ci_cd_ENABLE_CPPCHECK
      ci_cd_ENABLE_COVERAGE
      ci_cd_ENABLE_PCH
      ci_cd_ENABLE_CACHE)
  endif()

  ci_cd_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (ci_cd_ENABLE_SANITIZER_ADDRESS OR ci_cd_ENABLE_SANITIZER_THREAD OR ci_cd_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(ci_cd_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(ci_cd_global_options)
  if(ci_cd_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    ci_cd_enable_ipo()
  endif()

  ci_cd_supports_sanitizers()

  if(ci_cd_ENABLE_HARDENING AND ci_cd_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR ci_cd_ENABLE_SANITIZER_UNDEFINED
       OR ci_cd_ENABLE_SANITIZER_ADDRESS
       OR ci_cd_ENABLE_SANITIZER_THREAD
       OR ci_cd_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${ci_cd_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${ci_cd_ENABLE_SANITIZER_UNDEFINED}")
    ci_cd_enable_hardening(ci_cd_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(ci_cd_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(ci_cd_warnings INTERFACE)
  add_library(ci_cd_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  ci_cd_set_project_warnings(
    ci_cd_warnings
    ${ci_cd_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(ci_cd_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(ci_cd_options)
  endif()

  include(cmake/Sanitizers.cmake)
  ci_cd_enable_sanitizers(
    ci_cd_options
    ${ci_cd_ENABLE_SANITIZER_ADDRESS}
    ${ci_cd_ENABLE_SANITIZER_LEAK}
    ${ci_cd_ENABLE_SANITIZER_UNDEFINED}
    ${ci_cd_ENABLE_SANITIZER_THREAD}
    ${ci_cd_ENABLE_SANITIZER_MEMORY})

  set_target_properties(ci_cd_options PROPERTIES UNITY_BUILD ${ci_cd_ENABLE_UNITY_BUILD})

  if(ci_cd_ENABLE_PCH)
    target_precompile_headers(
      ci_cd_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(ci_cd_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    ci_cd_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(ci_cd_ENABLE_CLANG_TIDY)
    ci_cd_enable_clang_tidy(ci_cd_options ${ci_cd_WARNINGS_AS_ERRORS})
  endif()

  if(ci_cd_ENABLE_CPPCHECK)
    ci_cd_enable_cppcheck(${ci_cd_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(ci_cd_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    ci_cd_enable_coverage(ci_cd_options)
  endif()

  if(ci_cd_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(ci_cd_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(ci_cd_ENABLE_HARDENING AND NOT ci_cd_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR ci_cd_ENABLE_SANITIZER_UNDEFINED
       OR ci_cd_ENABLE_SANITIZER_ADDRESS
       OR ci_cd_ENABLE_SANITIZER_THREAD
       OR ci_cd_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    ci_cd_enable_hardening(ci_cd_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
