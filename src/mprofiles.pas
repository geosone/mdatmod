unit mprofiles;
{$mode objfpc}{$H+}
interface
// Facts measured by compiling official records.112; no vendor record source is embedded.
// Offsets are zero-based; String[N] stores a length byte plus N reserved bytes.
type
    TField = record
        Name: string[32];
        Offset: LongInt;
        Maximum: Byte;
    end;
    TProfile = record
        Name: string[16];
        DocsHash: string[64];
        DataVersion: string[8];
        ConfigSize: LongInt;
        FieldCount: Integer;
        Fields: array[0..15] of TField;
    end;
const
    Profiles: array[0..4] of TProfile = (
        (Name:'1.12 A44'; DocsHash:'729879504266147bd32240ddd7e4dced76b68e474ca0c432b8bb707a5b95570b'; DataVersion:'1.12 A44'; ConfigSize:5282; FieldCount:11; Fields:(
            (Name:'SystemPath'; Offset:17; Maximum:80),
            (Name:'DataPath'; Offset:98; Maximum:80),
            (Name:'LogsPath'; Offset:179; Maximum:80),
            (Name:'MsgsPath'; Offset:260; Maximum:80),
            (Name:'ThemePath'; Offset:341; Maximum:80),
            (Name:'SemaPath'; Offset:584; Maximum:80),
            (Name:'InboundPath'; Offset:665; Maximum:80),
            (Name:'UnsecurePath'; Offset:4646; Maximum:80),
            (Name:'OutboundPath'; Offset:908; Maximum:80),
            (Name:'BBSName'; Offset:989; Maximum:30),
            (Name:'SysopName'; Offset:1020; Maximum:30),
            (Name:''; Offset:0; Maximum:0),
            (Name:''; Offset:0; Maximum:0),
            (Name:''; Offset:0; Maximum:0),
            (Name:''; Offset:0; Maximum:0),
            (Name:''; Offset:0; Maximum:0)
        )),
        (Name:'1.12 A46'; DocsHash:'838f8edf29fbffaf0b34b31d7d12efd05b5ab639c2ee0c00a3e21acce2d76735'; DataVersion:'1.12 A46'; ConfigSize:5282; FieldCount:11; Fields:(
            (Name:'SystemPath'; Offset:17; Maximum:80),
            (Name:'DataPath'; Offset:98; Maximum:80),
            (Name:'LogsPath'; Offset:179; Maximum:80),
            (Name:'MsgsPath'; Offset:260; Maximum:80),
            (Name:'ThemePath'; Offset:341; Maximum:80),
            (Name:'SemaPath'; Offset:584; Maximum:80),
            (Name:'InboundPath'; Offset:665; Maximum:80),
            (Name:'UnsecurePath'; Offset:4646; Maximum:80),
            (Name:'OutboundPath'; Offset:908; Maximum:80),
            (Name:'BBSName'; Offset:989; Maximum:30),
            (Name:'SysopName'; Offset:1020; Maximum:30),
            (Name:''; Offset:0; Maximum:0),
            (Name:''; Offset:0; Maximum:0),
            (Name:''; Offset:0; Maximum:0),
            (Name:''; Offset:0; Maximum:0),
            (Name:''; Offset:0; Maximum:0)
        )),
        (Name:'1.12 A47'; DocsHash:'060731e9a78e4ebafb201842ea21ed184c158fb41c5f530722c6e3e814595b08'; DataVersion:'1.12 A47'; ConfigSize:8192; FieldCount:15; Fields:(
            (Name:'SystemPath'; Offset:17; Maximum:80),
            (Name:'DataPath'; Offset:98; Maximum:80),
            (Name:'LogsPath'; Offset:179; Maximum:80),
            (Name:'MsgsPath'; Offset:260; Maximum:80),
            (Name:'ThemePath'; Offset:341; Maximum:80),
            (Name:'Python2Lib'; Offset:422; Maximum:80),
            (Name:'Python3Lib'; Offset:503; Maximum:80),
            (Name:'SemaPath'; Offset:584; Maximum:80),
            (Name:'InboundPath'; Offset:665; Maximum:80),
            (Name:'UnsecurePath'; Offset:746; Maximum:80),
            (Name:'OutboundPath'; Offset:827; Maximum:80),
            (Name:'AttachPath'; Offset:908; Maximum:80),
            (Name:'BBSName'; Offset:989; Maximum:30),
            (Name:'BBSLocation'; Offset:1020; Maximum:30),
            (Name:'SysopName'; Offset:1051; Maximum:30),
            (Name:''; Offset:0; Maximum:0)
        )),
        (Name:'1.12 A48'; DocsHash:'7aec6ca491c5868d7c43d33298c910d092e8b2902df02ff634cef6bfe2cb99ef'; DataVersion:'1.12 A47'; ConfigSize:8192; FieldCount:15; Fields:(
            (Name:'SystemPath'; Offset:17; Maximum:80),
            (Name:'DataPath'; Offset:98; Maximum:80),
            (Name:'LogsPath'; Offset:179; Maximum:80),
            (Name:'MsgsPath'; Offset:260; Maximum:80),
            (Name:'ThemePath'; Offset:341; Maximum:80),
            (Name:'Python2Lib'; Offset:422; Maximum:80),
            (Name:'Python3Lib'; Offset:503; Maximum:80),
            (Name:'SemaPath'; Offset:584; Maximum:80),
            (Name:'InboundPath'; Offset:665; Maximum:80),
            (Name:'UnsecurePath'; Offset:746; Maximum:80),
            (Name:'OutboundPath'; Offset:827; Maximum:80),
            (Name:'AttachPath'; Offset:908; Maximum:80),
            (Name:'BBSName'; Offset:989; Maximum:30),
            (Name:'BBSLocation'; Offset:1020; Maximum:30),
            (Name:'SysopName'; Offset:1051; Maximum:30),
            (Name:''; Offset:0; Maximum:0)
        )),
        (Name:'1.12 A49'; DocsHash:'4575a20c3cb3c7ec3180e98ab2edbef7ae44da417f870c2e314e1874d1068363'; DataVersion:'1.12 A49'; ConfigSize:8192; FieldCount:15; Fields:(
            (Name:'SystemPath'; Offset:17; Maximum:80),
            (Name:'DataPath'; Offset:98; Maximum:80),
            (Name:'LogsPath'; Offset:179; Maximum:80),
            (Name:'MsgsPath'; Offset:260; Maximum:80),
            (Name:'ThemePath'; Offset:341; Maximum:80),
            (Name:'Python2Lib'; Offset:422; Maximum:80),
            (Name:'Python3Lib'; Offset:503; Maximum:80),
            (Name:'SemaPath'; Offset:584; Maximum:80),
            (Name:'InboundPath'; Offset:665; Maximum:80),
            (Name:'UnsecurePath'; Offset:746; Maximum:80),
            (Name:'OutboundPath'; Offset:827; Maximum:80),
            (Name:'AttachPath'; Offset:908; Maximum:80),
            (Name:'BBSName'; Offset:989; Maximum:30),
            (Name:'BBSLocation'; Offset:1020; Maximum:30),
            (Name:'SysopName'; Offset:1051; Maximum:30),
            (Name:''; Offset:0; Maximum:0)
        ))
    );
implementation
end.
