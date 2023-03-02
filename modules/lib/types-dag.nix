{ lib }:

let
  inherit (lib)
    concatStringsSep defaultFunctor fixedWidthNumber hm imap1 isAttrs isList
    length listToAttrs mapAttrs mkIf mkOrder mkOption mkOptionType nameValuePair
    stringLength types warn;

  dagEntryOf = elemType:
    let
      submoduleType = types.submodule ({ name, ... }: {
        options = {
          data = mkOption { type = elemType; };
          after = mkOption { type = with types; listOf str; };
          before = mkOption { type = with types; listOf str; };
        };
        config = mkIf (elemType.name == "submodule") {
          data._module.args.dagName = name;
        };
      });
      maybeConvert = def:
        if hm.dag.isEntry def.value then
          def.value
        else
          hm.dag.entryAnywhere (if def ? priority then
            mkOrder def.priority def.value
          else
            def.value);
    in mkOptionType {
      name = "dagEntryOf";
      description = "DAG entry of ${elemType.description}";
      # leave the checking to the submodule type
      merge = loc: defs:
        submoduleType.merge loc (map (def: {
          inherit (def) file;
          value = maybeConvert def;
        }) defs);
    };

in rec {
  # A directed acyclic graph of some inner type.
  #
  # Note, if the element type is a submodule then the `name` argument
  # will always be set to the string "data" since it picks up the
  # internal structure of the DAG values. To give access to the
  # "actual" attribute name a new submodule argument is provided with
  # the name `dagName`.
  dagOf = elemType:
    let attrEquivalent = types.attrsOf (dagEntryOf elemType);
    in mkOptionType rec {
      name = "dagOf";
      description = "DAG of ${elemType.description}";
      inherit (attrEquivalent) check merge emptyValue;
      getSubOptions = prefix: elemType.getSubOptions (prefix ++ [ "<name>" ]);
      getSubModules = elemType.getSubModules;
      substSubModules = m: dagOf (elemType.substSubModules m);
      functor = (defaultFunctor name) // { wrapped = elemType; };
      nestedTypes.elemType = elemType;
    };

  # A directed acyclic graph of some inner type OR a list of that
  # inner type. This is a temporary hack for use by the
  # `programs.ssh.matchBlocks` and is only guaranteed to be vaguely
  # correct!
  #
  # In particular, adding a dependency on one of the "unnamed-N-M"
  # entries generated by a list value is almost guaranteed to destroy
  # the list's order.
  #
  # This function will be removed in version 20.09.
  listOrDagOf = elemType:
    let
      paddedIndexStr = list: i:
        let padWidth = stringLength (toString (length list));
        in fixedWidthNumber padWidth i;

      convertAll = loc: defs:
        let
          convertListValue = namePrefix: def:
            let
              vs = def.value;
              pad = paddedIndexStr vs;
              makeEntry = i: v: nameValuePair "${namePrefix}.${pad i}" v;
              warning = ''
                In file ${def.file}
                a list is being assigned to the option '${
                  concatStringsSep "." loc
                }'.
                This will soon be an error due to the list form being deprecated.
                Please use the attribute set form instead with DAG functions to
                express the desired order of entries.
              '';
            in warn warning (listToAttrs (imap1 makeEntry vs));

          convertValue = i: def:
            if isList def.value then
              convertListValue "unnamed-${paddedIndexStr defs i}" def
            else
              def.value;
        in imap1 (i: def: def // { value = convertValue i def; }) defs;

      dagType = dagOf elemType;
    in mkOptionType rec {
      name = "listOrDagOf";
      description = "list or DAG of ${elemType.description}s";
      check = x: isList x || dagType.check x;
      merge = loc: defs: dagType.merge loc (convertAll loc defs);
      getSubOptions = dagType.getSubOptions;
      getSubModules = dagType.getSubModules;
      substSubModules = m: listOrDagOf (elemType.substSubModules m);
      functor = (defaultFunctor name) // { wrapped = elemType; };
    };
}