program WriterLayoutProbe;
{$mode objfpc}{$H+}
uses SysUtils;
const OSBIT = '/probe';
{$I records.112}
var Config:RecConfig; Server:ServerInfoRecord; Event:RecEvent;
procedure Check(const Name:string; Field,Base:Pointer; Size,ExpectedOffset,ExpectedSize:PtrUInt);
var Offset:PtrUInt;
begin
    Offset:=PtrUInt(Field)-PtrUInt(Base);
    if (Offset<>ExpectedOffset) or (Size<>ExpectedSize) then
        raise Exception.Create('Unexpected vendor field layout: '+Name);
    Writeln(Name,'.Offset=',Offset);
    Writeln(Name,'.Bytes=',Size);
end;
begin
    if (SizeOf(Config)<>8192) or (SizeOf(Server)<>384) or (SizeOf(Event)<>640) then
        raise Exception.Create('Unexpected vendor record size.');
    Writeln('Config.Bytes=',SizeOf(Config));
    Writeln('Server.Bytes=',SizeOf(Server));
    Writeln('Event.Bytes=',SizeOf(Event));
    Check('Config.SystemPath',@Config.SystemPath,@Config,SizeOf(Config.SystemPath),17,81);
    Check('Config.DataPath',@Config.DataPath,@Config,SizeOf(Config.DataPath),98,81);
    Check('Config.LogsPath',@Config.LogsPath,@Config,SizeOf(Config.LogsPath),179,81);
    Check('Config.MsgsPath',@Config.MsgsPath,@Config,SizeOf(Config.MsgsPath),260,81);
    Check('Config.ThemePath',@Config.ThemePath,@Config,SizeOf(Config.ThemePath),341,81);
    Check('Config.Python2Lib',@Config.Python2Lib,@Config,SizeOf(Config.Python2Lib),422,81);
    Check('Config.Python3Lib',@Config.Python3Lib,@Config,SizeOf(Config.Python3Lib),503,81);
    Check('Config.SemaPath',@Config.SemaPath,@Config,SizeOf(Config.SemaPath),584,81);
    Check('Config.InboundPath',@Config.InboundPath,@Config,SizeOf(Config.InboundPath),665,81);
    Check('Config.UnsecurePath',@Config.UnsecurePath,@Config,SizeOf(Config.UnsecurePath),746,81);
    Check('Config.OutboundPath',@Config.OutboundPath,@Config,SizeOf(Config.OutboundPath),827,81);
    Check('Config.AttachPath',@Config.AttachPath,@Config,SizeOf(Config.AttachPath),908,81);
    Check('Config.BBSName',@Config.BBSName,@Config,SizeOf(Config.BBSName),989,31);
    Check('Config.BBSLocation',@Config.BBSLocation,@Config,SizeOf(Config.BBSLocation),1020,31);
    Check('Config.SysopName',@Config.SysopName,@Config,SizeOf(Config.SysopName),1051,31);
    Check('Server.Active',@Server.Active,@Server,SizeOf(Server.Active),0,1);
    Check('Server.IPv4Adapter',@Server.IPv4Adapter,@Server,SizeOf(Server.IPv4Adapter),1,20);
    Check('Server.IPv6Adapter',@Server.IPv6Adapter,@Server,SizeOf(Server.IPv6Adapter),21,40);
    Check('Server.AdapterType',@Server.AdapterType,@Server,SizeOf(Server.AdapterType),61,1);
    Check('Server.ProtID',@Server.ProtID,@Server,SizeOf(Server.ProtID),66,9);
    Check('Server.Port',@Server.Port,@Server,SizeOf(Server.Port),75,2);
    Check('Server.MaxAllowed',@Server.MaxAllowed,@Server,SizeOf(Server.MaxAllowed),77,2);
    Check('Server.MaxIPs',@Server.MaxIPs,@Server,SizeOf(Server.MaxIPs),79,1);
    Check('Server.BanIP',@Server.BanIP,@Server,SizeOf(Server.BanIP),80,1);
    Check('Server.BanSecs',@Server.BanSecs,@Server,SizeOf(Server.BanSecs),81,2);
    Check('Server.TimeOut',@Server.TimeOut,@Server,SizeOf(Server.TimeOut),83,2);
    Check('Server.CountryBlock',@Server.CountryBlock,@Server,SizeOf(Server.CountryBlock),85,1);
    Check('Server.SendBlocked',@Server.SendBlocked,@Server,SizeOf(Server.SendBlocked),86,1);
    Check('Server.WebRoot',@Server.WebRoot,@Server,SizeOf(Server.WebRoot),96,81);
    Check('Server.SSLPort',@Server.SSLPort,@Server,SizeOf(Server.SSLPort),178,2);
    Check('Event.UID',@Event.UID,@Event,SizeOf(Event.UID),0,4);
    Check('Event.Active',@Event.Active,@Event,SizeOf(Event.Active),4,1);
    Check('Event.Name',@Event.Name,@Event,SizeOf(Event.Name),6,41);
    Check('Event.ExecType',@Event.ExecType,@Event,SizeOf(Event.ExecType),47,1);
    Check('Event.Shell',@Event.Shell,@Event,SizeOf(Event.Shell),57,161);
    Check('Event.Flags',@Event.Flags,@Event,SizeOf(Event.Flags),552,4);
{$ifdef PROFILE_A49}
    Check('Config.LogMIS.Level',@Config.LogMIS.Level,@Config,SizeOf(Config.LogMIS.Level),4573,1);
    Check('Config.LogMIS.RollType',@Config.LogMIS.RollType,@Config,SizeOf(Config.LogMIS.RollType),4574,1);
    Check('Config.LogMIS.Files',@Config.LogMIS.Files,@Config,SizeOf(Config.LogMIS.Files),4575,2);
    Check('Config.LogMIS.Size',@Config.LogMIS.Size,@Config,SizeOf(Config.LogMIS.Size),4577,4);
    Check('Config.LogMIS.Cached',@Config.LogMIS.Cached,@Config,SizeOf(Config.LogMIS.Cached),4581,1);
    Check('Config.LogMIS.DateFmt',@Config.LogMIS.DateFmt,@Config,SizeOf(Config.LogMIS.DateFmt),4582,26);
    Check('Config.LogNode.DateFmt',@Config.LogNode.DateFmt,@Config,SizeOf(Config.LogNode.DateFmt),4617,26);
    Check('Config.LogPOLL.DateFmt',@Config.LogPOLL.DateFmt,@Config,SizeOf(Config.LogPOLL.DateFmt),4652,26);
    Check('Config.LogQWK.DateFmt',@Config.LogQWK.DateFmt,@Config,SizeOf(Config.LogQWK.DateFmt),4687,26);
{$endif}
    Writeln('Status=PASS');
end.
