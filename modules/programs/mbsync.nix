{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.mbsync;

  # Accounts for which mbsync is enabled.
  mbsyncAccounts =
    filter (a: a.mbsync.enable) (attrValues config.accounts.email.accounts);

  genTlsConfig = tls:
    {
      SSLType = if !tls.enable then
        "None"
      else if tls.useStartTls then
        "STARTTLS"
      else
        "IMAPS";
    } // optionalAttrs (tls.enable && tls.certificatesFile != null) {
      CertificateFile = toString tls.certificatesFile;
    };

  masterSlaveMapping = {
    none = "None";
    imap = "Master";
    maildir = "Slave";
    both = "Both";
  };

  genSection = header: entries:
    let
      escapeValue = escape [ ''"'' ];
      hasSpace = v: builtins.match ".* .*" v != null;
      genValue = n: v:
        if isList v then
          concatMapStringsSep " " (genValue n) v
        else if isBool v then
          (if v then "yes" else "no")
        else if isInt v then
          toString v
        else if isString v && hasSpace v then
          ''"${escapeValue v}"''
        else if isString v then
          v
        else
          let prettyV = lib.generators.toPretty { } v;
          in throw "mbsync: unexpected value for option ${n}: '${prettyV}'";
    in ''
      ${header}
      ${concatStringsSep "\n"
      (mapAttrsToList (n: v: "${n} ${genValue n v}") entries)}
    '';

  genAccountConfig = account:
    with account;
    genSection "IMAPAccount ${name}" ({
      Host = imap.host;
      User = userName;
      PassCmd = toString passwordCommand;
    } // genTlsConfig imap.tls
      // optionalAttrs (imap.port != null) { Port = toString imap.port; }
      // mbsync.extraConfig.account) + "\n"
    + genSection "IMAPStore ${name}-remote"
    ({ Account = name; } // mbsync.extraConfig.remote) + "\n"
    + genSection "MaildirStore ${name}-local" ({
      Path = "${maildir.absPath}/";
      Inbox = "${maildir.absPath}/${folders.inbox}";
      SubFolders = "Verbatim";
    } // optionalAttrs (mbsync.flatten != null) { Flatten = mbsync.flatten; }
    // mbsync.extraConfig.local) + "\n"
    + genGroupChannelConfig name mbsync.groups
    + genAccountGroups mbsync.groups;

  genAccountWideChannel = account:
    with account;
    if mbsync != {} then
      genSection "Channel ${name}" ({
        Master = ":${name}-remote:";
        Slave = ":${name}-local:";
        Patterns = mbsync.patterns;
        Create = masterSlaveMapping.${mbsync.create};
        Remove = masterSlaveMapping.${mbsync.remove};
        Expunge = masterSlaveMapping.${mbsync.expunge};
        SyncState = "*";
      } // mbsync.extraConfig.channel) + "\n"
    else
      "";

  # Given the attr set of groups, return a string of channels that will direct
  # mail to the proper directories, according to the pattern used in channel's
  # master pattern definition.
  genGroupChannelConfig = storeName: groups:
    let
      # Given the name of the group this channel is part of and the channel
      # itself, generate the string for the desired configuration.
      genChannelString = groupName: channel:
        let
          escapeValue = escape [ ''\"'' ];
          hasSpace = v: builtins.match ".* .*" v != null;
          # Given a list of patterns, will return the string requested.
          # Only prints if the pattern is NOT the empty list, the default.
          genChannelPatterns = patterns: if (length patterns) != 0 then
            "Pattern " + concatStringsSep " " (map
              (pat: if hasSpace pat then escapeValue pat else pat) patterns) + "\n"
          else "";
        in
        genSection "Channel ${groupName}-${channel.name}" ({
          Master = ":${storeName}-remote:${channel.masterPattern}";
          Slave = ":${storeName}-local:${channel.slavePattern}";
        } // channel.extraConfig)
        + genChannelPatterns channel.patterns
        + "\n";
      # Given the group name, and a attr set of channels within that group,
      # Generate a list of strings for each channels' configuration.
      genChannelStrings = groupName: channels: optionals (channels != { })
        (mapAttrsToList (channelName: info: genChannelString groupName info) channels);
      # Given a group, return a string that configures all the channels within
      # the group.
      genGroupsChannels = group: concatStrings
        (genChannelStrings group.name group.channels);
    in
      # Generate all channel configurations for all groups for this account.
      concatStringsSep "\n"
        (mapAttrsToList (name: group: genGroupsChannels group) groups);

  # Given the attr set of groups, return a string which maps channels to groups
  genAccountGroups = groups:
    let
      # Given the name of the group and the attribute set of channels, make
      # make "Channel <grpName>-<chnName>" for each channel to list os strings
      genChannelStrings = groupName: channels: mapAttrsToList
        (name: info: "Channel ${groupName}-${name}") channels;
      # Take in 1 group, construct the "Group <grpName>" header, and if the group
      # is NOT empty, construct each of the channels.
      genGroupChannelString = group: optionals (groups != { })
        ([("Group " + group.name)] ++
         (genChannelStrings group.name group.channels));
      # Given set of groups, generates list of strings, where each string is one
      # of the groups and its consituent channels.
      genGroupsStrings = mapAttrsToList (name: info: concatStringsSep "\n"
        (genGroupChannelString groups.${name})) groups;
    in (concatStringsSep "\n\n" genGroupsStrings) # Put all strings together.
       # 2 \n needed in concatStringsSep because last element genGroupsStrings
       # has no \n.
       + "\n\n"; # Additional spacing after this account's group setup.

  genGroupConfig = name: channels:
    let
      genGroupChannel = n: boxes: "Channel ${n}:${concatStringsSep "," boxes}";
    in concatStringsSep "\n"
    ([ "Group ${name}" ] ++ mapAttrsToList genGroupChannel channels);

in {
  options = {
    programs.mbsync = {
      enable = mkEnableOption "mbsync IMAP4 and Maildir mailbox synchronizer";

      package = mkOption {
        type = types.package;
        default = pkgs.isync;
        defaultText = literalExample "pkgs.isync";
        example = literalExample "pkgs.isync";
        description = "The package to use for the mbsync binary.";
      };

      groups = mkOption {
        type = types.attrsOf (types.attrsOf (types.listOf types.str));
        default = { };
        example = literalExample ''
          {
            inboxes = {
              account1 = [ "Inbox" ];
              account2 = [ "Inbox" ];
            };
          }
        '';
        description = ''
          Definition of groups.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra configuration lines to add to the mbsync configuration.
        '';
      };
    };

    accounts.email.accounts = mkOption {
      type = with types; attrsOf (submodule (import ./mbsync-accounts.nix));
    };
  };

  config = mkIf cfg.enable {
    assertions = let
      checkAccounts = pred: msg:
        let badAccounts = filter pred mbsyncAccounts;
        in {
          assertion = badAccounts == [ ];
          message = "mbsync: ${msg} for accounts: "
            + concatMapStringsSep ", " (a: a.name) badAccounts;
        };
    in [
      (checkAccounts (a: a.maildir == null) "Missing maildir configuration")
      (checkAccounts (a: a.imap == null) "Missing IMAP configuration")
      (checkAccounts (a: a.passwordCommand == null) "Missing passwordCommand")
      (checkAccounts (a: a.userName == null) "Missing username")
    ];

    home.packages = [ cfg.package ];

    programs.notmuch.new.ignore = [ ".uidvalidity" ".mbsyncstate" ];

    home.file.".mbsyncrc".text = let
      accountsConfig = map genAccountConfig mbsyncAccounts;
      groupsConfig = mapAttrsToList genGroupConfig cfg.groups;
    in concatStringsSep "\n" ([''
      # Generated by Home Manager.
    ''] ++ optional (cfg.extraConfig != "") cfg.extraConfig ++ accountsConfig
      ++ groupsConfig) + "\n";

    home.activation = mkIf (mbsyncAccounts != [ ]) {
      createMaildir =
        hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
          $DRY_RUN_CMD mkdir -m700 -p $VERBOSE_ARG ${
            concatMapStringsSep " " (a: a.maildir.absPath) mbsyncAccounts
          }
        '';
    };
  };
}
