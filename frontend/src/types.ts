export interface CoverageResponse {
  hit: number
  total: number
  pct: number
  missing: string[]
}

export interface BinInfo {
  name: string
  alpha: number
  beta: number
  priority: number
}

export interface BanditResponse {
  bins: BinInfo[]
}

export interface GenerateRequest {
  extensions: string[]
  count: number
  mode: string
  lengthMin: number
  lengthMax: number
}

export interface GenerateResponse {
  seqs: string[][]
  coverage: CoverageResponse
}

export interface ScenarioInfo {
  name: string
  tags: string[]
  extensions: string[]
  description: string
}

export interface ScenarioRunResponse {
  sequence: string[]
  coverageHits: string[]
}

export interface SSEEvent {
  coverage: CoverageResponse
  bandit: BanditResponse
}
