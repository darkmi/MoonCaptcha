///|
/// 统一响应模型：`{"repCode": "...", "repMsg": "...", "repData": ...}`。
/// rep_data 保存**已序列化**的 JSON 片段（对齐 Java 版 repData 为任意对象）。
pub struct ResponseModel {
  rep_code : String
  rep_msg : String
  rep_data : String?
}

///|
pub fn ResponseModel::success() -> ResponseModel {
  { rep_code: Success.code(), rep_msg: Success.message(), rep_data: None }
}

///|
pub fn ResponseModel::success_msg(message : String) -> ResponseModel {
  { rep_code: Success.code(), rep_msg: message, rep_data: None }
}

///|
pub fn ResponseModel::success_data(data_json : String) -> ResponseModel {
  {
    rep_code: Success.code(),
    rep_msg: Success.message(),
    rep_data: Some(data_json),
  }
}

///|
pub fn ResponseModel::error(code : RepCode) -> ResponseModel {
  { rep_code: code.code(), rep_msg: code.message(), rep_data: None }
}

///|
pub fn ResponseModel::error_msg(
  code : RepCode,
  message : String,
) -> ResponseModel {
  { rep_code: code.code(), rep_msg: message, rep_data: None }
}

///|
/// 对齐 RepCodeEnum.BLANK_ERROR.parseError(field)："field不能为空"。
pub fn ResponseModel::blank_error(field : String) -> ResponseModel {
  ResponseModel::error_msg(BlankError, "\{field}不能为空")
}

///|
pub fn ResponseModel::rep_code(self : ResponseModel) -> String {
  self.rep_code
}

///|
pub fn ResponseModel::is_success(self : ResponseModel) -> Bool {
  self.rep_code == Success.code()
}

///|
/// 序列化为协议 JSON。repData 为原始 JSON 片段时直接内嵌。
pub fn ResponseModel::to_json(self : ResponseModel) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"repCode\":")
  buf.write_string(@common.json_escape_string(self.rep_code))
  buf.write_string(",\"repMsg\":")
  buf.write_string(@common.json_escape_string(self.rep_msg))
  match self.rep_data {
    Some(data) => {
      buf.write_string(",\"repData\":")
      buf.write_string(data)
    }
    None => ()
  }
  buf.write_string("}")
  buf.to_string()
}
