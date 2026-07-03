import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** FluxDown 开源仓库地址 */
export const GITHUB_REPO_URL = "https://github.com/zerx-lab/FluxDown";

/** Web 版演示站地址（登录页不识别 URL 携带的 token，演示令牌见文档 /docs 的 Web 界面页） */
export const DEMO_URL = "https://demo.zerx.dev/";
