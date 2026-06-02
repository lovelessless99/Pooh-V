import axios from 'axios'
import type {
  GenerateRequest, GenerateResponse, CoverageResponse,
  BanditResponse, ScenarioInfo, ScenarioRunResponse
} from '@/types'

const BASE = '/api'

export const api = {
  generate: (req: GenerateRequest) =>
    axios.post<GenerateResponse>(`${BASE}/generate`, req),
  getCoverage: () =>
    axios.get<CoverageResponse>(`${BASE}/coverage`),
  resetCoverage: () =>
    axios.post(`${BASE}/coverage/reset`),
  getBandit: () =>
    axios.get<BanditResponse>(`${BASE}/bandit`),
  getScenarios: () =>
    axios.get<ScenarioInfo[]>(`${BASE}/scenarios`),
  runScenario: (name: string) =>
    axios.post<ScenarioRunResponse>(`${BASE}/scenarios/${name}/run`),
}
