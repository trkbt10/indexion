///|
pub type AgentOrientConfig = @model.AgentOrientConfig

///|
pub type AgentOrientEvidence = @model.AgentOrientEvidence

///|
pub type AgentOrientItem = @model.AgentOrientItem

///|
pub type AgentOrientMap = @model.AgentOrientMap

///|
pub type AgentOrientMapFile = @model.AgentOrientMapFile

///|
pub type AgentOrientMapOwner = @model.AgentOrientMapOwner

///|
pub type AgentOrientMapStatus = @model.AgentOrientMapStatus

///|
pub type AgentOrientQuizItem = @model.AgentOrientQuizItem

///|
pub type AgentOrientReport = @model.AgentOrientReport

///|
pub async fn orient_agent(config : AgentOrientConfig) -> AgentOrientReport {
  @orient.orient_agent(config)
}

///|
pub fn orient_map_path(config : AgentOrientConfig) -> String {
  @orient.orient_map_path(config)
}
