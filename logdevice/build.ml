module B = Mbuild.Build
module R = Mbuild.Rule
module C = Mbuild.Cmd
module Cf = Mbuild.Cfun
module Cx = Mbuild.Cxxfun

let proj_build_dir = "build_"
let proj_build_install_dir = Filename.concat proj_build_dir "install"

let proj_build_install_hdr_dir =
  Filename.concat proj_build_install_dir "include"

let proj_build_install_lib_dir = Filename.concat proj_build_install_dir "lib"
let proj_build_install_bin_dir = Filename.concat proj_build_install_dir "bin"
let proj_link_tbl = Hashtbl.create 64

let show_link_tbl tbl =
  Hashtbl.iter
    (fun k v ->
      let () = Printf.printf "%s: " k in
      let () = List.iter (fun d -> Printf.printf "%s " d) v in
      print_endline "")
    tbl

(* add leaf node *)
let normalize_link_tbl tbl =
  let need_add = Hashtbl.create 16 in
  let () =
    Hashtbl.iter
      (fun _ qs ->
        List.iter
          (fun q ->
            match Hashtbl.find_opt tbl q with
            | Some _ -> ()
            | None -> Hashtbl.replace need_add q true)
          qs)
      tbl
  in
  Hashtbl.iter (fun k _ -> Hashtbl.add tbl k []) need_add

let has_cycle tbl start =
  let visited = Hashtbl.create 64 in
  let rec f p =
    let () = Hashtbl.add visited p true in
    let qs = Hashtbl.find tbl p in
    List.fold_left
      (fun prev q ->
        if prev then true
        else
          match Hashtbl.find_opt visited q with Some _ -> true | None -> f q)
      false qs
  in
  f start

let cc_link_tbl tbl start =
  let visited = Hashtbl.create 64 in
  let cycle_edges = Hashtbl.create 16 in
  let rec f p =
    let () = Hashtbl.add visited p true in
    let qs = Hashtbl.find tbl p in
    List.iter
      (fun q ->
        match Hashtbl.find_opt visited q with
        | Some _ -> Hashtbl.add cycle_edges p q
        | None -> f q)
      qs
  in

  let () = f start in

  let tbl_copy = Hashtbl.create 64 in
  let () =
    Hashtbl.iter
      (fun k v ->
        match Hashtbl.find_opt visited k with
        | Some _ -> Hashtbl.add tbl_copy k v
        | None -> ())
      tbl
  in

  let rec alias name iter =
    let prefix = String.make (iter + 1) '#' in
    let alias_name = prefix ^ "@" ^ name in
    match Hashtbl.find_opt tbl_copy alias_name with
    | Some _ -> alias name (iter + 1)
    | None -> alias_name
  in

  let () =
    Hashtbl.iter
      (fun a b ->
        let ads = Hashtbl.find tbl_copy a in
        let new_ads = List.filter (fun d -> not (String.equal d b)) ads in
        let new_b = alias b 0 in
        let () = Hashtbl.replace tbl_copy a (List.append new_ads [ new_b ]) in
        Hashtbl.add tbl_copy new_b [])
      cycle_edges
  in

  if has_cycle tbl_copy start then failwith "has cycle"
  else
    (*
    let () = print_endline "no cycle !!!!!!!!!!!!!!!!!!" in
    *)
    tbl_copy

let topsort tbl =
  let revert () =
    let tbl_rev = Hashtbl.create 64 in
    let () =
      Hashtbl.iter
        (fun k v ->
          let () =
            match Hashtbl.find_opt tbl_rev k with
            | Some _ -> ()
            | None -> Hashtbl.add tbl_rev k []
          in
          List.iter
            (fun x ->
              match Hashtbl.find_opt tbl_rev x with
              | Some ov -> Hashtbl.replace tbl_rev x (List.append ov [ k ])
              | None -> Hashtbl.add tbl_rev x [ k ])
            v)
        tbl
    in
    tbl_rev
  in

  let tbl_rev = revert () in

  (*
  let () = show_link_tbl tbl_rev in
  *)
  let rec f tb prev =
    (*
    let () =
      print_endline "-----------------------------------------------------"
    in
    let () = List.iter (fun x -> print_endline x) prev in
    let () = show_link_tbl tb in
    *)
    if Hashtbl.length tb == 0 then prev
    else
      (*
      let () = print_endline (string_of_int (Hashtbl.length tb)) in
      *)
      let zs =
        Hashtbl.fold
          (fun q ps zs ->
            if List.length ps == 0 then List.append zs [ q ] else zs)
          tb []
      in
      let new_tb =
        List.fold_left
          (fun t z ->
            let nt = Hashtbl.copy t in
            let () =
              Hashtbl.iter
                (fun q ps ->
                  let new_ps =
                    List.filter (fun p -> not (String.equal p z)) ps
                  in
                  Hashtbl.replace nt q new_ps)
                t
            in
            nt)
          tb zs
      in
      let () = List.iter (fun z -> Hashtbl.remove new_tb z) zs in
      (* let () = Unix.sleep 1 in *)
      f new_tb (List.append prev zs)
  in

  let order = f tbl_rev [] in
  List.map
    (fun s ->
      let ss = String.split_on_char '@' s in
      if List.length ss == 1 then List.hd ss
      else if List.length ss == 2 then List.nth ss 1
      else failwith "error lib name")
    order

let get_linker_deps_list ~name =
  (*
  let () = show_link_tbl proj_link_tbl in
  *)
  let () = normalize_link_tbl proj_link_tbl in
  (*
  let () = show_link_tbl proj_link_tbl in
  *)
  (*
  let () =
    print_endline "-----------------------------------------------------"
  in
    *)
  let link_tbl = cc_link_tbl proj_link_tbl name in
  (*
  let () = show_link_tbl link_tbl in
  *)
  let link_list = topsort link_tbl in

  (*
  let () =
    print_endline "-----------------------------------------------------"
  in
  let () = List.iter (fun x -> print_endline x) link_list in
  *)
  link_list

let thrift_libs =
  [
    "thriftcpp2";
    "transport";
    "thriftfrozen2";
    "async";
    "thrift-core";
    "thriftprotocol";
    "concurrency";
    "thriftmetadata";
    "rpcmetadata";
  ]

let thrift_deps =
  List.concat
    [
      thrift_libs;
      [ "wangle" ];
      (* ${FOLLY_LIBRARIES} *)
      [ "folly"; "follybenchmark" ];
      (* ${FIZZ_LIBRARIES} *)
      [ "fizz" ];
      (* ## ${LIBSODIUM_LIBRARIES} *)
      [ "sodium" ];
      (* ${FMT_LIBRARIES} *)
      [ "fmt" ];
      (* ${BZIP2_LIBRARIES} *)
      [ "bz2" ];
      (* ${ZLIB_LIBRARIES} *)
      [ "z" ];
      (* ${Boost_LIBRARIES} *)
      [
        "boost_context";
        "boost_chrono";
        "boost_date_time";
        "boost_filesystem";
        "boost_program_options";
        "boost_regex";
        "boost_system";
        "boost_thread";
        "boost_atomic";
      ];
      (* ${OPENSSL_LIBRARIES} *)
      [ "ssl"; "crypto" ];
      (* ${ZSTD_LIBRARY} *)
      [ "zstd" ];
      (* ${GLOG_LIBRARIES} *)
      [ "glog" ];
      (* ${LIBGFLAGS_LIBRARY} *)
      [ "gflags" ];
      (* ${SNAPPY_LIBRARY} *)
      [ "snappy"; "pthread" ];
      (* ${LIBLZMA_LIBRARIES} *)
      [ "lzma" ];
    ]

let logdevice_deps =
  List.concat
    [
      (* ${THRIFT_DEPS} *)
      thrift_deps;
      (* ${ROCKSDB_LIBRARIES} *)
      [ "rocksdb" ];
      (* ${LIBSODIUM_LIBRARIES} *)
      [ "sodium" ];
      (* ${FOLLY_BENCHMARK_LIBRARIES} *)
      [ "follybenchmark" ];
      (* ${FOLLY_LIBRARIES} *)
      [ "folly" ];
      (* ${FOLLY_TEST_UTIL_LIBRARIES} *)

      (* ${LIBUNWIND_LIBRARIES} *)
      [ "unwind" ];
      (* ${ZLIB_LIBRARIES} *)
      [ "z" ];
      (* ${Boost_LIBRARIES} *)
      [
        "boost_context";
        "boost_chrono";
        "boost_date_time";
        "boost_filesystem";
        "boost_program_options";
        "boost_regex";
        "boost_system";
        "boost_thread";
        "boost_atomic";
      ];
      (* ${OPENSSL_LIBRARIES} *)
      [ "ssl" ];
      (* ${ZSTD_LIBRARY} *)
      [ "zstd" ];
      (* ${LIBEVENT_LIB} *)
      [ "event" ];
      (* ${LIBEVENT_LIB_SSL} *)
      [ "event_openssl" ];
      (* ${LIBDL_LIBRARIES} *)
      [ "dl" ];
      (* ${DOUBLE_CONVERSION_LIBRARY} *)
      [ "double-conversion" ];
      (* ${Zookeeper_LIBRARY} *)
      [ "zookeeper_mt" ];
      (* ${CPR_LIBRARY} *)
      [ "cpr"; "curl" ];
      (* ${Gason_LIBRARY} *)
      [ "gason_static" ];
      (* ${GLOG_LIBRARIES} *)
      [ "glog" ];
      (* ${LIBGFLAGS_LIBRARY} *)
      [ "gflags" ];
      (* ${LZ4_LIBRARY} *)
      [ "lz4" ];
      (* ${IBERTY_LIBRARIES} *)
      [ "iberty" ];
      (* ${BZIP2_LIBRARIES} *)
      [ "bz2" ];
      (* ${ZLIB_LIBRARIES} *)
      [ "z" ];
      (* ${JEMALLOC_LIBRARIES} *)
      [ "jemalloc" ];
      (* ${IBERTY_LIBRARIES} *)
      [ "iberty" ];
      (* ${SNAPPY_LIBRARY} *)
      [ "snappy" ];
      (* ${PYTHON_LIBRARIES} *)
      (* python3.10.a *)
      [ "pthread" ];
      (* ${LIBLZMA_LIBRARIES} *)
      [ "lzma" ];
    ]

let rec auto_sources ~suffix ~dir ~recurse =
  if Sys.is_directory dir then
    let subs = Array.to_list (Sys.readdir dir) in
    if recurse then
      let sr =
        List.map
          (fun s -> auto_sources ~suffix ~dir:(Filename.concat dir s) ~recurse)
          subs
      in
      List.concat sr
    else
      List.filter
        (fun s -> (not (Sys.is_directory s)) && Filename.check_suffix s suffix)
        (List.map (fun f -> Filename.concat dir f) subs)
  else List.filter (fun s -> Filename.check_suffix s suffix) [ dir ]

let remove_matches l p =
  let r = Str.regexp_string p in
  List.filter
    (fun s ->
      try
        let _ = Str.search_forward r s 0 in
        false
      with Not_found -> true)
    l

let cmake ~name ~opts ~src_dir ~build_dir ~install_dir ~outputs ~deps () =
  let gen_cmd =
    List.concat
      [
        [ "cmake" ];
        [
          "-DCMAKE_POSITION_INDEPENDENT_CODE=ON";
          "-DCMAKE_PREFIX_PATH="
          ^ Filename.concat (Unix.getcwd ()) proj_build_install_dir;
          "-DCMAKE_LIBRARY_PATH="
          ^ Filename.concat (Unix.getcwd ()) proj_build_install_lib_dir;
          "-DCMAKE_INCLUDE_PATH="
          ^ Filename.concat (Unix.getcwd ()) proj_build_install_hdr_dir;
        ];
        opts;
        [ "-G"; "Ninja"; "-S"; src_dir; "-B"; build_dir ];
      ]
  in
  let gen_cmd = C.make gen_cmd in
  let build_cmd = C.make [ "cmake"; "--build"; build_dir ] in
  let install_cmd =
    C.make
      [
        "cmake";
        "--install";
        build_dir;
        "--prefix";
        Filename.concat proj_build_dir "install";
      ]
  in
  let targets = List.map (fun o -> R.File o) outputs in
  let rule =
    R.create_m targets ~deps ~cmds:[ gen_cmd; build_cmd; install_cmd ]
  in
  let ar = R.create (R.Phony name) ~deps:outputs in
  [ ar; rule ]

let fmt () =
  let outputs = [ Filename.concat proj_build_install_lib_dir "libfmt.a" ] in
  let deps = [] in
  let name = "fmt" in
  let src_dir = "external/fmt" in
  let build_dir = Filename.concat proj_build_dir "fmt" in
  let install_dir = proj_build_install_dir in
  let opts =
    [
      "-DCMAKE_POSITION_INDEPENDENT_CODE=True";
      "-DCMAKE_CXX_STANDARD=17";
      "-DFMT_TEST=OFF";
    ]
  in
  cmake ~name ~opts ~src_dir ~build_dir ~install_dir ~outputs ~deps ()

let folly () =
  let outputs =
    [
      Filename.concat proj_build_install_lib_dir "libfolly.a";
      Filename.concat proj_build_install_lib_dir "libfollybenchmark.a";
    ]
  in
  let deps = [ "fmt" ] in
  let name = "folly" in
  let src_dir = "external/folly" in
  let build_dir = Filename.concat proj_build_dir "folly" in
  let install_dir = proj_build_install_dir in
  let opts =
    [
      "-DCMAKE_POSITION_INDEPENDENT_CODE=True";
      "-DBUILD_SHARED_LIBS=OFF";
      "-DCMAKE_CXX_STANDARD=17";
      "-DFOLLY_USE_JEMALLOC=OFF";
      "-DPYTHON_EXTENSIONS=False";
    ]
  in
  cmake ~name ~opts ~src_dir ~build_dir ~install_dir ~outputs ~deps ()

let fizz () =
  let outputs = [ Filename.concat proj_build_install_lib_dir "libfizz.a" ] in
  let deps = [ "folly" ] in
  let name = "fizz" in
  let src_dir = "external/fizz/fizz" in
  let build_dir = Filename.concat proj_build_dir "fizz" in
  let install_dir = proj_build_install_dir in
  let opts =
    [
      "-DCMAKE_POSITION_INDEPENDENT_CODE=True";
      "-DBUILD_SHARED_LIBS=OFF";
      "-DCMAKE_CXX_STANDARD=17";
      "-DBUILD_TESTS=OFF";
      "-DBUILD_EXAMPLES=OFF";
    ]
  in
  cmake ~name ~opts ~src_dir ~build_dir ~install_dir ~outputs ~deps ()

let wangle () =
  let outputs = [ Filename.concat proj_build_install_lib_dir "libwangle.a" ] in
  let deps = [ "fizz"; "folly" ] in
  let name = "wangle" in
  let src_dir = "external/wangle/wangle" in
  let build_dir = Filename.concat proj_build_dir "wangle" in
  let install_dir = proj_build_install_dir in
  let opts =
    [
      "-DCMAKE_POSITION_INDEPENDENT_CODE=True";
      "-DBUILD_SHARED_LIBS=OFF";
      "-DCMAKE_CXX_STANDARD=17";
      "-DBUILD_TESTS=OFF";
    ]
  in
  cmake ~name ~opts ~src_dir ~build_dir ~install_dir ~outputs ~deps ()

let fbthrift () =
  let outputs =
    [
      Filename.concat proj_build_install_bin_dir "thrift1";
      Filename.concat proj_build_install_lib_dir "libthriftcpp2.a";
      Filename.concat proj_build_install_lib_dir "libtransport.a";
      Filename.concat proj_build_install_lib_dir "libthriftfrozen2.a";
      Filename.concat proj_build_install_lib_dir "libasync.a";
      Filename.concat proj_build_install_lib_dir "libthrift-core.a";
      Filename.concat proj_build_install_lib_dir "libthriftprotocol.a";
      Filename.concat proj_build_install_lib_dir "libconcurrency.a";
      Filename.concat proj_build_install_lib_dir "libthriftmetadata.a";
      Filename.concat proj_build_install_lib_dir "librpcmetadata.a";
    ]
  in
  let deps = [ "fizz"; "folly"; "wangle" ] in
  let name = "fbthrift" in
  let src_dir = "external/fbthrift" in
  let build_dir = Filename.concat proj_build_dir "fbthrift" in
  let install_dir = proj_build_install_dir in
  let opts =
    [
      "-Dthriftpy3=OFF";
      "-DCMAKE_POSITION_INDEPENDENT_CODE=True";
      "-DBUILD_SHARED_LIBS=OFF";
      "-DCMAKE_CXX_STANDARD=17";
      "-Denable_tests=OFF";
    ]
  in
  cmake ~name ~opts ~src_dir ~build_dir ~install_dir ~outputs ~deps ()

let rocksdb () =
  let deps = [] in
  let outputs = [ Filename.concat proj_build_dir "rocksdb/librocksdb.a" ] in
  let name = "rocksdb" in
  let src_dir = "external/rocksdb" in
  let build_dir = Filename.concat proj_build_dir "rocksdb" in
  let install_dir = proj_build_install_dir in
  let opts =
    [
      "-DCMAKE_CXX_STANDARD=17";
      "-DWITH_TESTS=OFF";
      "-DWITH_TOOLS=OFF";
      "-DWITH_CORE_TOOLS=OFF";
      "-DWITH_BENCHMARK_TOOLS=OFF";
      "-DWITH_BZ2=ON";
      "-DWITH_LZ4=ON";
      "-DWITH_SNAPPY=ON";
      "-DWITH_ZLIB=ON";
      "-DWITH_ZSTD=ON";
      "-DCMAKE_POSITION_INDEPENDENT_CODE=True";
    ]
  in
  let rules =
    cmake ~name ~opts ~src_dir ~build_dir ~install_dir ~outputs ~deps ()
  in

  (* this is a patch: rocksdb's cmake install do not install librocksdb.a *)
  let install_cmd =
    C.make
      [
        "cp";
        Filename.concat build_dir "librocksdb.a";
        proj_build_install_lib_dir;
      ]
  in
  List.concat
    [
      rules;
      [
        R.create
          (R.File (Filename.concat proj_build_install_lib_dir "librocksdb.a"))
          ~cmds:[ install_cmd ] ~deps:outputs;
      ];
    ]

let flatbuffers () =
  let output = Filename.concat proj_build_install_hdr_dir "flatbuffers" in
  let name = "flatbuffers" in
  let src_dir = "external/flatbuffers/src" in
  let header_dir = Filename.concat src_dir "include/flatbuffers" in
  let install_dir = Filename.concat proj_build_install_dir "include" in
  let cmd = C.make [ "cp"; "-R"; header_dir; install_dir ] in
  [
    R.create (R.File output) ~cmds:[ cmd ];
    R.create (R.Phony name) ~deps:[ output ];
  ]

let gason () =
  let output = Filename.concat proj_build_install_lib_dir "libgason_static.a" in
  let name = "gason" in
  let src_dir = "external/gason/src/src" in
  let build_dir = Filename.concat proj_build_dir "gason" in
  let rules =
    Cx.static_lib ~cxxflags:[ "-fPIC" ] ~build_dir
      [ Filename.concat src_dir "gason.cpp" ]
      "gason_static"
  in
  let install_hdr_cmd =
    C.make
      [ "cp"; Filename.concat src_dir "gason.h"; proj_build_install_hdr_dir ]
  in
  let install_lib_cmd =
    C.make
      [
        "cp";
        Filename.concat build_dir "libgason_static.a";
        proj_build_install_lib_dir;
      ]
  in
  let installed_lib =
    Filename.concat proj_build_install_lib_dir "libgason_static.a"
  in
  let install_rule =
    R.create (R.File installed_lib)
      ~deps:[ Filename.concat build_dir "libgason_static.a" ]
      ~cmds:[ install_hdr_cmd; install_lib_cmd ]
  in
  List.append rules [ install_rule; R.create (R.Phony name) ~deps:[ output ] ]

let cpr () =
  let name = "cpr" in
  let src_dir = Filename.concat "external" "cpr" in
  let build_dir = Filename.concat proj_build_dir "cpr" in
  let install_dir = proj_build_install_dir in
  let outputs = [ Filename.concat proj_build_install_lib_dir "libcpr.a" ] in
  let deps = [] in

  let opts =
    [
      "-DCMAKE_CXX_STANDARD=17";
      "-DBUILD_SHARED_LIBS=OFF";
      "-DBUILD_TESTING=OFF";
      "-DCPR_ENABLE_SSL=OFF";
      "-DCPR_FORCE_USE_SYSTEM_CURL=ON";
    ]
  in
  cmake ~name ~opts ~src_dir ~build_dir ~install_dir ~outputs ~deps ()

(*
thrift_library(
  #file_name
  #services
  #language
  #options
  #file_path
  #output_path
)
*)
let thrift_library ~file_name ~services ~language ~options ~file_path
    ~output_path ~thrift_include_dirs ~include_prefix ~thrift1
    ~extra_src_include_dirs =
  let gen suffix =
    String.concat "/"
      [ output_path; "gen-" ^ language; file_name ^ "_" ^ suffix ]
  in
  let gen_hdrs =
    [
      gen "constants.h";
      gen "data.h";
      gen "metadata.h";
      gen "types.h";
      gen "types.tcc";
    ]
  in
  let gen_srcs =
    [ gen "constants.cpp"; gen "data.cpp"; gen "types.cpp"; gen "metadata.cpp" ]
  in
  let gen_services service suffix =
    String.concat "/" [ output_path; "gen-" ^ language; service ^ suffix ]
  in
  let gen_services_hdr service =
    [
      gen_services service ".h";
      gen_services service ".tcc";
      gen_services service "AsyncClient.h";
      gen_services service "_custom_protocol.h";
    ]
  in
  let gen_services_src service =
    [ gen_services service ".cpp"; gen_services service "AsyncClient.cpp" ]
  in
  let services_hdr = List.concat_map gen_services_hdr services in
  let services_src = List.concat_map gen_services_src services in
  let hdr = List.append gen_hdrs services_hdr in
  let src = List.append gen_srcs services_src in
  let gen_language = "mstch_cpp2" in
  let thrift_file = file_path ^ "/" ^ file_name ^ ".thrift" in

  let include_opts = List.map (fun d -> "-I " ^ d) thrift_include_dirs in

  let create_dir_cmd = C.make [ "mkdir"; "-p"; output_path ] in
  (* thrift1 --gen mstch_cpp2:include_prefix=/path/to/prefix/ -o build_/logdevice/common/fb303/if common/if/for_open_source/common/fb303/if *)
  let thrift1_cmd =
    C.make
      [
        thrift1;
        "--gen";
        gen_language ^ ":json," ^ "include_prefix=" ^ include_prefix;
        "-o";
        output_path;
        C.make include_opts;
        thrift_file;
      ]
  in
  let f s = R.File s in
  let targets = List.concat [ List.map f hdr; List.map f src ] in
  let gen_rule =
    R.create_m ~deps:[ thrift1; thrift_file ]
      ~cmds:[ create_dir_cmd; thrift1_cmd ]
      targets
  in
  let src_include_dirs =
    List.append
      [
        proj_build_install_hdr_dir;
        Filename.concat proj_build_dir "logdevice";
        proj_build_dir;
      ]
      extra_src_include_dirs
  in
  let cxxflags = List.map (fun i -> "-I " ^ i) src_include_dirs in
  let cxxflags = List.append [ "-fPIC"; "-std=c++17" ] cxxflags in
  let lib_rules =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      src (file_name ^ "-cpp2")
  in
  let phony_rule =
    R.create
      (R.Phony (file_name ^ "-cpp2-target"))
      ~deps:(List.map R.target lib_rules)
  in
  List.concat [ [ gen_rule ]; lib_rules; [ phony_rule ] ]

let ld_common_fb303_if () =
  let deps = [ "fbthrift" ] in
  let file_path = "common/if/for_open_source/common/fb303/if" in
  let include_prefix = "common/fb303/if" in
  let output_path = Filename.concat proj_build_dir include_prefix in
  let thrift_lib_rules =
    thrift_library ~file_name:"fb303" ~services:[ "FacebookService" ]
      ~language:"cpp2" ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) thrift_lib_rules

let ld_common_if () =
  let deps = [ "fbthrift" ] in
  let file_path = "common/if" in
  let include_prefix = "logdevice/common/if" in
  let output_path = Filename.concat proj_build_dir include_prefix in
  let common_lib =
    thrift_library ~file_name:"common" ~services:[] ~language:"cpp2" ~options:[]
      ~file_path ~output_path ~include_prefix ~thrift_include_dirs:[]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  let payload_lib =
    thrift_library ~file_name:"payload" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  let apimodel_lib =
    thrift_library ~file_name:"ApiModel" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  let apiservice_thrift_include_dirs = [ "common/if/for_open_source"; "../" ] in
  let apiservice_lib =
    thrift_library ~file_name:"ApiService" ~services:[ "LogDeviceAPI" ]
      ~language:"cpp2" ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:apiservice_thrift_include_dirs
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  let rules =
    List.concat [ common_lib; payload_lib; apimodel_lib; apiservice_lib ]
  in
  let rules = List.map (fun r -> R.add_deps r deps) rules in

  let () =
    Hashtbl.add proj_link_tbl "ApiService-cpp2"
      [ "ApiModel-cpp2"; "fb303-cpp2" ]
  in
  let () = Hashtbl.add proj_link_tbl "common-cpp2" [ "payload-cpp2" ] in

  rules

let ld_common_configuration_if () =
  let deps = [ "fbthrift" ] in
  let file_path = "common/configuration/if" in
  let include_prefix = "logdevice/common/configuration/if" in
  let output_path = Filename.concat proj_build_dir include_prefix in
  let lib =
    thrift_library ~file_name:"AllReadStreamsDebugConfig" ~services:[]
      ~language:"cpp2" ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) lib

let ld_common_configuration_utils () =
  let deps = [ "fbthrift" ] in
  let file_path = "common/configuration/utils" in
  let include_prefix = "logdevice/common/configuration/utils" in

  let output_path = Filename.concat proj_build_dir include_prefix in
  let lib =
    thrift_library ~file_name:"ConfigurationCodec" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) lib

let ld_common_configuration_nodes () =
  let deps = [ "fbthrift"; "Membership-cpp2-target" ] in
  let file_path = "common/configuration/nodes" in
  let include_prefix = "logdevice/common/configuration/nodes" in

  let () =
    Hashtbl.add proj_link_tbl "NodesConfiguration-cpp2" [ "Membership-cpp2" ]
  in

  let output_path = Filename.concat proj_build_dir include_prefix in
  let lib =
    thrift_library ~file_name:"NodesConfiguration" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) lib

let ld_common_configuration_logs_if () =
  let deps = [ "fbthrift"; "common-cpp2-target" ] in
  let file_path = "common/configuration/logs/if" in
  let include_prefix = "logdevice/logsconfig" in

  let () = Hashtbl.add proj_link_tbl "logsconfig-cpp2" [ "common-cpp2" ] in

  let output_path = Filename.concat proj_build_dir include_prefix in
  let lib =
    thrift_library ~file_name:"logsconfig" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) lib

let ld_common_membership () =
  let deps = [ "fbthrift" ] in
  let file_path = "common/membership" in
  let include_prefix = "logdevice/common/membership" in

  let output_path = Filename.concat proj_build_dir include_prefix in
  let lib =
    thrift_library ~file_name:"Membership" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) lib

let ld_common_replicated_state_machine_if () =
  let deps = [ "fbthrift" ] in
  let file_path = "common/replicated_state_machine/if" in
  let include_prefix = "logdevice/common/replicated_state_machine/if" in

  let output_path = Filename.concat proj_build_dir include_prefix in
  let lib =
    thrift_library ~file_name:"KeyValueStore" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) lib

let ld_common () =
  let fb303 = ld_common_fb303_if () in
  let common_if = ld_common_if () in
  let configuration_if = ld_common_configuration_if () in
  let configuration_utils = ld_common_configuration_utils () in
  let configuration_nodes = ld_common_configuration_nodes () in
  let configuration_logs_if = ld_common_configuration_logs_if () in
  let common_membership = ld_common_membership () in
  let replicated_state_machine_if = ld_common_replicated_state_machine_if () in

  let () =
    Hashtbl.add proj_link_tbl "common"
      [
        "common-cpp2";
        "ApiService-cpp2";
        "logsconfig-cpp2";
        "Membership-cpp2";
        "NodesConfiguration-cpp2";
        "ConfigurationCodec-cpp2";
        "KeyValueStore-cpp2";
        "AllReadStreamsDebugConfig-cpp2";
      ]
  in

  let cpp_files = auto_sources ~suffix:"cpp" ~dir:"common" ~recurse:true in
  let cpp_files = remove_matches cpp_files "/test/" in
  let common_include_dirs =
    [
      "../";
      proj_build_install_hdr_dir;
      proj_build_dir;
      Filename.concat proj_build_dir "logdevice";
    ]
  in
  let common_cxxflags = List.map (fun d -> "-I " ^ d) common_include_dirs in
  let common_cxxflags = List.append [ "-std=c++17"; "-fPIC" ] common_cxxflags in
  let common =
    Cx.static_lib ~cxxflags:common_cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      cpp_files "common"
  in
  let deps =
    [
      "folly";
      "flatbuffers";
      "gason";
      "cpr";
      "ApiService-cpp2-target";
      "NodesConfiguration-cpp2-target";
      "ConfigurationCodec-cpp2-target";
      "AllReadStreamsDebugConfig-cpp2-target";
    ]
  in
  let common = List.map (fun r -> R.add_deps r deps) common in

  List.concat
    [
      fb303;
      common_if;
      configuration_if;
      configuration_utils;
      configuration_nodes;
      configuration_logs_if;
      common_membership;
      replicated_state_machine_if;
      common;
    ]

let ld_lib_checkpointing_if () =
  let deps = [ "fbthrift" ] in
  let file_path = "lib/checkpointing/if" in
  let include_prefix = "logdevice/lib/checkpointing/if" in
  let output_path = Filename.concat proj_build_dir include_prefix in
  let thrift_lib_rules =
    thrift_library ~file_name:"Checkpoint" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) thrift_lib_rules

let ld_lib () =
  let deps =
    [ "rocksdb"; "folly"; "fbthrift"; "common"; "Checkpoint-cpp2-target" ]
  in
  let name = "ldclient_static" in

  let () = Hashtbl.add proj_link_tbl name [ "common"; "Checkpoint-cpp2" ] in

  let cpp_files = auto_sources ~suffix:"cpp" ~dir:"lib" ~recurse:true in
  let cpp_files = remove_matches cpp_files "/test/" in
  let include_dirs =
    [
      "../";
      proj_build_install_hdr_dir;
      proj_build_dir;
      Filename.concat proj_build_dir "logdevice";
    ]
  in
  let cxxflags = List.map (fun d -> "-I " ^ d) include_dirs in
  let cxxflags = List.append [ "-fPIC"; "-std=c++17" ] cxxflags in
  let static_lib =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      cpp_files name
  in
  let static_lib = List.map (fun r -> R.add_deps r deps) static_lib in

  let () =
    Hashtbl.add proj_link_tbl "logdevice" [ "common"; "Checkpoint-cpp2" ]
  in
  let link_list = get_linker_deps_list ~name:"logdevice" in
  let link_dir =
    [ proj_build_install_lib_dir; Filename.concat proj_build_dir "logdevice" ]
  in
  let ldflags = List.map (fun d -> "-L " ^ d) link_dir in
  let ldflags = List.append ldflags [ "-fuse-ld=lld" ] in
  let libs = List.append (List.tl link_list) logdevice_deps in
  let shared_lib =
    Cx.shared_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      ~ldflags ~libs cpp_files "logdevice"
  in
  let shared_lib = List.map (fun r -> R.add_deps r deps) shared_lib in

  List.concat [ ld_lib_checkpointing_if (); static_lib; shared_lib ]

let ld_server_epoch_store_if () =
  let deps = [ "fbthrift"; "common-cpp2-target" ] in
  let file_path = "server/epoch_store/if" in
  let include_prefix = "logdevice/server/epoch_store/if" in

  let () = Hashtbl.add proj_link_tbl "EpochStore-cpp2" [ "common-cpp2" ] in

  let output_path = Filename.concat proj_build_dir include_prefix in
  let lib =
    thrift_library ~file_name:"EpochStore" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  List.map (fun r -> R.add_deps r deps) lib

let ld_server () =
  let epoch_store_if = ld_server_epoch_store_if () in

  let () =
    Hashtbl.add proj_link_tbl "logdevice_server_core"
      [
        "common";
        "ApiService-cpp2";
        "EpochStore-cpp2";
        "ldclient_static";
        "logdevice_admin_settings";
        "logdevice_admin_maintenance";
      ]
  in

  let cpp_files = auto_sources ~suffix:"cpp" ~dir:"server" ~recurse:true in
  let cpp_files = remove_matches cpp_files "/test/" in
  let cpp_files = remove_matches cpp_files "/locallogstore/test/" in
  let cpp_files = remove_matches cpp_files "/admincommands/" in
  let cpp_files = remove_matches cpp_files "server/main.cpp" in
  let cpp_files = remove_matches cpp_files "server/Server.cpp" in
  let cpp_files = remove_matches cpp_files "server/shutdown.cpp" in
  let include_dirs =
    [
      "../";
      proj_build_install_hdr_dir;
      proj_build_dir;
      Filename.concat proj_build_dir "logdevice";
    ]
  in
  let cxxflags = List.map (fun d -> "-I " ^ d) include_dirs in
  let cxxflags = List.append [ "-std=c++17"; "-fPIC" ] cxxflags in
  let server_core =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      cpp_files "logdevice_server_core"
  in
  let deps =
    [
      "common";
      "ApiService-cpp2-target";
      "EpochStore-cpp2-target";
      "ldclient_static";
      "logdevice_admin_settings";
      "logdevice_admin_maintenance" (*
  ${LOGDEVICE_EXTERNAL_DEPS})
  *);
    ]
  in
  let server_core = List.map (fun r -> R.add_deps r deps) server_core in
  List.concat [ epoch_store_if; server_core ]

let ld_admin_if () =
  let common_deps =
    [ "fbthrift"; "common-cpp2-target"; "Membership-cpp2-target" ]
  in
  let file_path = "admin/if" in
  let include_prefix = "logdevice/admin/if" in
  let output_path = Filename.concat proj_build_dir include_prefix in
  let thrift_sources_and_deps =
    [
      ( "exceptions",
        [ "fbthrift"; "common-cpp2-target"; "Membership-cpp2-target" ] );
      ( "settings",
        [ "fbthrift"; "common-cpp2-target"; "Membership-cpp2-target" ] );
      ("logtree", [ "fbthrift"; "common-cpp2-target"; "Membership-cpp2-target" ]);
      ("nodes", [ "fbthrift"; "common-cpp2-target"; "Membership-cpp2-target" ]);
      ( "cluster_membership",
        [
          "fbthrift";
          "common-cpp2-target";
          "Membership-cpp2-target";
          "nodes-cpp2-target";
        ] );
      ( "admin_commands",
        [ "fbthrift"; "common-cpp2-target"; "Membership-cpp2-target" ] );
      ( "safety",
        [
          "fbthrift";
          "common-cpp2-target";
          "Membership-cpp2-target";
          "nodes-cpp2-target";
        ] );
      ( "maintenance",
        [
          "fbthrift";
          "common-cpp2-target";
          "Membership-cpp2-target";
          "nodes-cpp2-target";
          "safety-cpp2-target";
        ] );
    ]
  in

  let f (ts, ts_deps) =
    let libs =
      let () =
        Hashtbl.add proj_link_tbl (ts ^ "-cpp2")
          [ "common-cpp2"; "Membership-cpp2" ]
      in

      thrift_library ~file_name:ts ~services:[] ~language:"cpp2" ~options:[]
        ~file_path ~output_path ~include_prefix ~thrift_include_dirs:[ "../" ]
        ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
        ~extra_src_include_dirs:[]
    in
    List.map (fun r -> R.add_deps r ts_deps) libs
  in
  let thrift_libs = List.concat (List.map f thrift_sources_and_deps) in
  let thrift_libs = List.map (fun r -> R.add_deps r common_deps) thrift_libs in

  let admin =
    thrift_library ~file_name:"admin" ~services:[ "AdminAPI" ] ~language:"cpp2"
      ~options:[] ~file_path ~output_path ~include_prefix
      ~thrift_include_dirs:[ "../"; "common/if/for_open_source" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  let common_libs_target =
    [
      "maintenance-cpp2-target";
      "safety-cpp2-target";
      "settings-cpp2-target";
      "nodes-cpp2-target";
      "cluster_membership-cpp2-target";
      "admin_commands-cpp2-target";
      "logtree-cpp2-target";
      "common-cpp2-target";
      "exceptions-cpp2-target";
    ]
  in

  let common_libs =
    [
      "maintenance-cpp2";
      "safety-cpp2";
      "settings-cpp2";
      "nodes-cpp2";
      "cluster_membership-cpp2";
      "admin_commands-cpp2";
      "logtree-cpp2";
      "common-cpp2";
      "exceptions-cpp2";
    ]
  in

  let () =
    Hashtbl.add proj_link_tbl "admin-cpp2"
      (List.concat [ common_libs; [ "fb303-cpp2" ] ])
  in

  let admin_deps =
    List.append common_libs_target [ "fbthrift"; "fb303-cpp2-target" ]
  in
  let admin = List.map (fun r -> R.add_deps r admin_deps) admin in
  List.concat [ thrift_libs; admin ]

let ld_admin () =
  let admin_if = ld_admin_if () in

  let safety_cpp_files =
    auto_sources ~suffix:"cpp" ~dir:"admin/safety" ~recurse:true
  in
  let admin_settings_cpp_files =
    auto_sources ~suffix:"cpp" ~dir:"admin/settings" ~recurse:true
  in

  let admin_membership_cpp_files =
    auto_sources ~suffix:"cpp" ~dir:"admin/cluster_membership" ~recurse:false
  in
  let maintenance_cpp_files =
    auto_sources ~suffix:"cpp" ~dir:"admin/maintenance" ~recurse:false
  in

  let admin_cpp_files =
    auto_sources ~suffix:"cpp" ~dir:"admin" ~recurse:false
  in
  let admin_cpp_files = remove_matches admin_cpp_files "/test/" in
  let admin_cpp_files = remove_matches admin_cpp_files "/maintenance/test/" in
  let admin_cpp_files = remove_matches admin_cpp_files "AdminAPIUtils.cpp" in
  let admin_cpp_files = remove_matches admin_cpp_files "Conv.cpp" in

  let include_dirs =
    [
      "../";
      proj_build_install_hdr_dir;
      proj_build_dir;
      Filename.concat proj_build_dir "logdevice";
    ]
  in
  let cxxflags = List.map (fun d -> "-I " ^ d) include_dirs in
  let cxxflags = List.append [ "-fPIC"; "-std=c++17" ] cxxflags in

  let admin_util_deps =
    [
      "admin-cpp2-target";
      "logdevice_safety_checker";
      "admin-cpp2-target";
      "common";
    ]
  in

  let () =
    Hashtbl.add proj_link_tbl "logdevice_admin_util"
      [ "logdevice_safety_checker"; "admin-cpp2"; "common" ]
  in

  let admin_util =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      [ "admin/AdminAPIUtils.cpp"; "admin/Conv.cpp" ]
      "logdevice_admin_util"
  in
  let admin_util =
    List.map (fun r -> R.add_deps r admin_util_deps) admin_util
  in

  let safety_checker_deps = [ "common"; "admin-cpp2-target" ] in

  let () =
    Hashtbl.add proj_link_tbl "logdevice_safety_checker"
      [ "common"; "logdevice_server" ]
  in

  let safety_checker =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      safety_cpp_files "logdevice_safety_checker"
  in
  let safety_checker =
    List.map (fun r -> R.add_deps r safety_checker_deps) safety_checker
  in

  let admin_settings_deps = [ "common" ] in
  let () = Hashtbl.add proj_link_tbl "logdevice_admin_settings" [ "common" ] in
  let admin_settings =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      admin_settings_cpp_files "logdevice_admin_settings"
  in
  let admin_settings =
    List.map (fun r -> R.add_deps r admin_settings_deps) admin_settings
  in

  let admin_maintenance_deps =
    [
      "common";
      "logdevice_safety_checker";
      "logdevice_admin_util";
      "admin-cpp2-target";
      "MaintenanceDelta-cpp2-target";
      "fbthrift"
      (*
  ${FBTHRIFT_LIBRARIES}
  ${GLOG_LIBRARIES}
  ${LIBGFLAGS_LIBRARY}
  *);
    ]
  in
  let () =
    Hashtbl.add proj_link_tbl "logdevice_admin_maintenance"
      [
        "common";
        "logdevice_safety_checker";
        "logdevice_admin_util";
        "admin-cpp2";
        "MaintenanceDelta-cpp2";
      ]
  in
  let admin_maintenance =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      maintenance_cpp_files "logdevice_admin_maintenance"
  in
  let admin_maintenance =
    List.map (fun r -> R.add_deps r admin_maintenance_deps) admin_maintenance
  in

  let admin_deps =
    [
      "common";
      "logdevice_admin_settings";
      "logdevice_safety_checker";
      "admin-cpp2-target";
      "MaintenanceDelta-cpp2-target";
      "logdevice_server_core";
      "fbthrift"
      (*
  ${FBTHRIFT_LIBRARIES}
  ${GLOG_LIBRARIES}
  ${LIBGFLAGS_LIBRARY}
  *);
    ]
  in
  let () =
    Hashtbl.add proj_link_tbl "logdevice_admin"
      [
        "common";
        "logdevice_admin_settings";
        "logdevice_safety_checker";
        "admin-cpp2";
        "MaintenanceDelta-cpp2";
        "logdevice_server_core";
      ]
  in

  let admin =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      (List.concat [ admin_cpp_files; admin_membership_cpp_files ])
      "logdevice_admin"
  in
  let admin = List.map (fun r -> R.add_deps r admin_deps) admin in

  let maintenance_delta_deps =
    [
      "fbthrift";
      "maintenance-cpp2-target";
      "Membership-cpp2-target";
      "admin-cpp2-target";
    ]
  in
  let () =
    Hashtbl.add proj_link_tbl "MaintenanceDelta-cpp2"
      [ "Membership-cpp2"; "admin-cpp2" ]
  in
  let maintenance_delta_file_path = "admin/maintenance" in
  let maintenance_delta_include_prefix = "logdevice/admin/maintenance" in
  let maintenance_delta_output_path =
    Filename.concat proj_build_dir maintenance_delta_include_prefix
  in
  let maintenance_delta =
    thrift_library ~file_name:"MaintenanceDelta" ~services:[] ~language:"cpp2"
      ~options:[] ~file_path:maintenance_delta_file_path
      ~output_path:maintenance_delta_output_path
      ~include_prefix:maintenance_delta_include_prefix
      ~thrift_include_dirs:[ "../" ]
      ~thrift1:(Filename.concat proj_build_install_bin_dir "thrift1")
      ~extra_src_include_dirs:[]
  in
  let maintenance_delta =
    List.map (fun r -> R.add_deps r maintenance_delta_deps) maintenance_delta
  in

  List.concat
    [
      admin_util;
      safety_checker;
      admin_settings;
      admin_maintenance;
      admin;
      maintenance_delta;
      admin_if;
    ]

let ld_ops_admin_server () =
  let deps = [ "logdevice_server" ] in
  let srcs = auto_sources ~suffix:"cpp" ~dir:"ops/admin_server" ~recurse:true in

  let include_dirs =
    [
      "../";
      proj_build_install_hdr_dir;
      proj_build_dir;
      Filename.concat proj_build_dir "logdevice";
    ]
  in
  let cxxflags = List.map (fun d -> "-I " ^ d) include_dirs in
  let cxxflags = List.append [ "-std=c++17"; "-fPIC" ] cxxflags in

  let () = Hashtbl.add proj_link_tbl "ld-admin-server" [ "logdevice_server" ] in
  let link_list = get_linker_deps_list ~name:"ld-admin-server" in
  let link_dir =
    [ proj_build_install_lib_dir; Filename.concat proj_build_dir "logdevice" ]
  in
  let ldflags = List.map (fun d -> "-L " ^ d) link_dir in
  let ldflags = List.append ldflags [ "-fuse-ld=lld" ] in
  let libs = List.append (List.tl link_list) logdevice_deps in
  let admin_server =
    Cx.exe ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      ~ldflags ~libs srcs "ld-admin-server"
  in
  let admin_server = List.map (fun r -> R.add_deps r deps) admin_server in
  admin_server

let ld_examples () =
  let deps = [ "logdevice"; "ldclient_static" ] in

  let include_dirs =
    [
      "../";
      proj_build_install_hdr_dir;
      proj_build_dir;
      Filename.concat proj_build_dir "logdevice";
    ]
  in
  let cxxflags = List.map (fun d -> "-I " ^ d) include_dirs in
  let cxxflags = List.append [ "-std=c++17"; "-fPIC" ] cxxflags in

  let () = Hashtbl.add proj_link_tbl "ldcat" [ "ldclient_static" ] in
  let link_list = get_linker_deps_list ~name:"ldcat" in
  let link_dir =
    [ proj_build_install_lib_dir; Filename.concat proj_build_dir "logdevice" ]
  in
  let ldflags = List.map (fun d -> "-L " ^ d) link_dir in
  let ldflags = List.append ldflags [ "-fuse-ld=lld" ] in
  let libs = List.append (List.tl link_list) logdevice_deps in

  let ldcat =
    Cx.exe ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      ~ldflags ~libs
      [ "examples/cat.cpp"; "examples/parse_target_log.cpp" ]
      "ldcat"
  in
  let ldcat = List.map (fun r -> R.add_deps r deps) ldcat in

  let ldwrite =
    Cx.exe ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      ~ldflags ~libs
      [ "examples/write.cpp"; "examples/parse_target_log.cpp" ]
      "ldwrite"
  in
  let ldwrite = List.map (fun r -> R.add_deps r deps) ldwrite in

  let ldtail =
    Cx.exe ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      ~ldflags ~libs
      [ "examples/tail.cpp"; "examples/parse_target_log.cpp" ]
      "ldtail"
  in
  let ldtail = List.map (fun r -> R.add_deps r deps) ldtail in

  List.concat [ ldcat; ldwrite; ldtail ]

let logdevice () =
  let ld_common = ld_common () in
  let ld_lib = ld_lib () in
  let ld_server = ld_server () in
  let ld_admin = ld_admin () in

  let admincommands_cpp_files =
    auto_sources ~suffix:"cpp" ~dir:"server/admincommands" ~recurse:true
  in
  let include_dirs =
    [
      "../";
      proj_build_install_hdr_dir;
      proj_build_dir;
      Filename.concat proj_build_dir "logdevice";
    ]
  in
  let cxxflags = List.map (fun d -> "-I " ^ d) include_dirs in
  let cxxflags = List.append [ "-std=c++17"; "-fPIC" ] cxxflags in
  let server_cpp_files =
    List.concat
      [
        admincommands_cpp_files; [ "server/Server.cpp"; "server/shutdown.cpp" ];
      ]
  in
  let server =
    Cx.static_lib ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      server_cpp_files "logdevice_server"
  in
  let server_deps =
    [
      "logdevice_server_core";
      "logdevice_admin";
      "ldclient_static";
      "fbthrift";
      "rocksdb";
    ]
  in
  let () =
    Hashtbl.add proj_link_tbl "logdevice_server"
      [ "logdevice_server_core"; "logdevice_admin"; "ldclient_static" ]
  in
  let server = List.map (fun r -> R.add_deps r server_deps) server in

  let logdeviced_srcs = [ "server/main.cpp" ] in
  let logdeviced_deps = [ "logdevice_server" ] in
  let () = Hashtbl.add proj_link_tbl "logdeviced" [ "logdevice_server" ] in
  let link_list = get_linker_deps_list ~name:"logdeviced" in
  let logdeviced_link_dir =
    [ proj_build_install_lib_dir; Filename.concat proj_build_dir "logdevice" ]
  in
  let logdeviced_ldflags = List.map (fun d -> "-L " ^ d) logdeviced_link_dir in
  let logdeviced_ldflags = List.append logdeviced_ldflags [ "-fuse-ld=lld" ] in
  let logdeviced_libs = List.append (List.tl link_list) logdevice_deps in
  let logdeviced =
    Cx.exe ~cxxflags
      ~build_dir:(Filename.concat proj_build_dir "logdevice")
      ~ldflags:logdeviced_ldflags ~libs:logdeviced_libs logdeviced_srcs
      "logdeviced"
  in
  let logdeviced =
    List.map (fun r -> R.add_deps r logdeviced_deps) logdeviced
  in

  let ld_admin_server = ld_ops_admin_server () in
  let ld_examples = ld_examples () in

  List.concat
    [
      ld_common;
      ld_lib;
      ld_server;
      ld_admin;
      server;
      logdeviced;
      ld_admin_server;
      ld_examples;
    ]

let () =
  let fmt_rules = fmt () in

  let folly_rules = folly () in

  let fizz_rules = fizz () in

  let wangle_rules = wangle () in

  let fbthrift_rules = fbthrift () in

  let rocksdb_rules = rocksdb () in

  let flatbuffers_rules = flatbuffers () in

  let gason_rules = gason () in

  let cpr_rules = cpr () in

  let ld_rules = logdevice () in

  let rules =
    List.concat
      [
        fmt_rules;
        folly_rules;
        fizz_rules;
        wangle_rules;
        fbthrift_rules;
        rocksdb_rules;
        flatbuffers_rules;
        gason_rules;
        cpr_rules;
        ld_rules;
      ]
  in
  let mbuild = B.create rules in
  let () = B.ninja mbuild ~build_dir:proj_build_dir in

  ()
