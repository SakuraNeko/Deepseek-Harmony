/**
 * 允许上传的文件后缀名管理模块
 * 用于 Web 组件 onShowFileSelector → DocumentViewPicker 过滤
 *
 * NOTE: fileSuffixFilters 数组长度不能超过 100，因此采用分组格式压缩
 * 格式：'描述|.ext1,.ext2,.ext3' 或 '.ext'
 */

// 图片类
const IMAGE_FILTER = '图片(.png,.jpg,.jpeg,.svg,.svgz,.bmp,.gif,.webp,.ico,.xbm,.dib,.pjp,.tif,.pjpeg,.avif,.apng,.tiff,.jfif,.avifs,.blp,.bufr,.bw,.cur,.dcx,.dds,.emf,.fit,.fits,.flc,.fli,.ftc,.ftu,.gbr,.grib,.h5,.hdf,.hif,.icb,.icns,.iim,.im,.j2c,.j2k,.jp2,.jpc,.jpe,.jpf,.jpx,.mpeg,.mpg,.msp,.pbm,.pcd,.pcx,.pfm,.pgm,.pnm,.ppm,.psd,.pxr,.qoi,.ras,.rgb,.rgba,.sgi,.tga,.vda,.vst,.wmf,.xpm,.epub,.mobi)';

// 文档类
const DOC_FILTER = '文档(.doc,.docx,.ppt,.pptx,.xls,.xlsx,.pdf,.epub,.mobi,.tex,.txt,.md,.csv,.tsv,.rtf,.odt,.ods,.odp,.pages,.numbers,.key)';

// 文本/标记/配置
const TEXT_FILTER = '文本(.txt,.md,.csv,.tsv,.html,.htm,.json,.log,.yaml,.yml,.ini,.conf,.toml,.xml,.cfg,.properties,.rst,.rest,.org,.wiki,.adoc,.asciidoc,.textile,.creole,.mustache,.jinja,.handlebars,.hbs,.liquid,.twig,.ttl,.rdf,.rss,.sparql)';

// 代码文件
const CODE_FILTER = '代码(.go,.h,.c,.cpp,.cxx,.cc,.cs,.java,.js,.css,.jsx,.ts,.tsx,.json5,.jsonld,.php,.py,.py3,.pyi,.pyx,.pyw,.rb,.rhtml,.swift,.kt,.ktm,.kts,.scala,.sbt,.rs,.dart,.lua,.pl,.pm,.groovy,.gvy,.gsp,.hs,.hsc,.hx,.elm,.erl,.hrl,.ex,.exs,.clj,.cljs,.cljc,.edn,.fs,.fsi,.fsx,.f90,.f,.f77,.f95,.for,.v,.vh,.sv,.svh,.vhdl,.vhd,.vhf,.vhi,.vho,.vhs,.vht,.vhw,.vala,.vapi,.sql,.cql,.asm,.s,.nasm,.cmake,.make,.mak,.mk,.ninja,.gradle,.xml,.xsd,.xsl,.xslt,.xquery,.xq,.wsdl,.wsf,.xaml,.xib,.plist,.props,.targets,.sh,.bash,.bat,.cmd,.zsh,.fish,.ps1,.psm1,.vim,.nginxconf,.R,.r,.rmd,.scm,.ss,.sls,.rkt,.matlab,.m,.sci,.sce,.scss,.sass,.less,.styl,.coffee,.cjsx,.iced,.cob,.cbl,.cobol,.cpy,.asp,.aspx,.asax,.ascx,.ashx,.asmx,.jsp,.cfm,.cfml,.cfc,.abap,.ada,.adb,.ads,.idr,.lidr,.d,.di,.cr,.cy,.jl,.krl,.lean,.lfe,.ls,.lgt,.mo,.monkey,.moon,.nim,.nimrod,.nu,.oz,.pas,.pike,.pmod,.pony,.purs,.red,.reds,.rebol,.reb,.self,.shen,.smali,.sqf,.st,.xtend,.yang,.zig,.env,.lock,.dockerfile,.gitignore,.gitmodules,.gitkeep,.example)';

// 数据/序列化
const DATA_FILTER = '数据(.csv,.tsv,.json,.json5,.jsonld,.xml,.yaml,.yml,.toml,.ini,.cfg,.conf,.properties,.proto,.pub,.pb,.pbi,.capnp,.h5,.hdf,.sqlite,.db,.pkl,.npy,.npz,.mat,.sav,.fits)';

// 合并（数组仅有 5 项，远低于 100 的上限）
export const ALLOWED_UPLOAD_EXTENSIONS: Array<string> = [
  IMAGE_FILTER,
  DOC_FILTER,
  TEXT_FILTER,
  CODE_FILTER,
  DATA_FILTER
];
