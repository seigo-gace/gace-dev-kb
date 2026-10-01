#!/usr/bin/env python3
from __future__ import annotations
import argparse, asyncio, json, os, sys, tempfile
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

def text_from_result(result):
    return '\n'.join(str(getattr(x,'text')) for x in (getattr(result,'content',None) or []) if getattr(x,'text',None))

def load(path:Path):
    rows=[json.loads(x) for x in path.read_text(encoding='utf-8').splitlines() if x.strip()]
    if not rows: raise RuntimeError('REUSABLE_ASSET_METADATA_EMPTY')
    return rows

def natural_query(row):
    discovery=row.get('discovery') if isinstance(row.get('discovery'),dict) else {}
    capabilities=discovery.get('capabilities') if isinstance(discovery.get('capabilities'),list) else []
    terms=[str(x) for x in capabilities if str(x).strip()]
    if discovery.get('purpose'): terms.append(str(discovery['purpose']))
    terms.append(str(row.get('summary') or row.get('name') or ''))
    return ' '.join(terms).strip()

async def wait(awaitable,seconds,label):
    try:
        async with asyncio.timeout(seconds): return await awaitable
    except TimeoutError as e: raise RuntimeError(f'{label}_TIMEOUT={seconds}s') from e

async def run(python:Path,root:Path,metadata:Path,expected:int,timeout:int):
    rows=load(metadata)
    if len(rows)!=expected: raise RuntimeError(f'REUSABLE_ASSET_COUNT_MISMATCH expected={expected} actual={len(rows)}')
    env=dict(os.environ); env['MCP_ENABLE_FILE_WATCHING']='false'; env['MCP_PROJECT_ROOT']=str(root); env['PYTHONDONTWRITEBYTECODE']='1'
    server=StdioServerParameters(command=str(python),args=['-m','mcp_vector_search.mcp',str(root)],env=env,cwd=str(root))
    kind_first={}
    with tempfile.TemporaryFile(mode='w+',encoding='utf-8') as errlog:
        try:
            async with stdio_client(server,errlog=errlog) as (rs,ws):
                async with ClientSession(rs,ws) as session:
                    init=await wait(session.initialize(),timeout,'MCP_INITIALIZE'); info=getattr(init,'server_info',None) or getattr(init,'serverInfo',None)
                    if not info: raise RuntimeError('MCP_SERVER_INFO_MISSING')
                    tools=await wait(session.list_tools(),timeout,'MCP_LIST_TOOLS'); names={x.name for x in tools.tools}
                    if 'search_code' not in names: raise RuntimeError('MCP_SEARCH_CODE_TOOL_MISSING')
                    print(f'MCP_REUSABLE_INITIALIZE=PASS TOOLS={len(names)}')
                    for row in rows:
                        kid=str(row.get('knowledge_id') or '')
                        if not kid: raise RuntimeError('REUSABLE_ASSET_KNOWLEDGE_ID_MISSING')
                        kind=str(row.get('asset_kind') or 'unknown'); kind_first.setdefault(kind,row)
                        result=await wait(session.call_tool('search_code',arguments={'query':kid,'limit':50,'similarity_threshold':0.0,'search_mode':'bm25','use_rerank':False,'expand':False}),timeout,f'MCP_REUSABLE_{kid}')
                        if getattr(result,'isError',False): raise RuntimeError(f'MCP_REUSABLE_TOOL_ERROR={kid}:{text_from_result(result)}')
                        if kid not in text_from_result(result): raise RuntimeError(f'MCP_REUSABLE_NOT_RETRIEVED={kid}')
                    print(f'MCP_REUSABLE_EXACT_SEARCH=PASS RECORDS={len(rows)}')
                    natural=0
                    for kind,row in sorted(kind_first.items()):
                        query=natural_query(row); kid=str(row['knowledge_id'])
                        if not query: continue
                        result=await wait(session.call_tool('search_code',arguments={'query':query,'limit':50,'similarity_threshold':0.0,'search_mode':'bm25','use_rerank':False,'expand':False}),timeout,f'MCP_REUSABLE_NATURAL_{kind}')
                        if getattr(result,'isError',False): raise RuntimeError(f'MCP_REUSABLE_NATURAL_TOOL_ERROR={kind}')
                        if kid not in text_from_result(result): raise RuntimeError(f'MCP_REUSABLE_NATURAL_EXPECTED_MISSING kind={kind} id={kid}')
                        natural+=1; print(f'MCP_REUSABLE_NATURAL_SEARCH=PASS KIND={kind} ID={kid}')
            errlog.flush(); errlog.seek(0); stderr=errlog.read()
            if 'Could not find entity matching' in stderr: raise RuntimeError('MCP_DOC_ONLY_KG_ENTITY_WARNING_PRESENT')
        except BaseException:
            errlog.flush(); errlog.seek(0); stderr=errlog.read().strip()
            if stderr: print(stderr,file=sys.stderr)
            raise
    print(f'GACE_REUSABLE_ASSET_MCP_E2E=PASS RECORDS={len(rows)} KINDS={len(kind_first)} NATURAL_CHECKS={natural}')

def main():
    p=argparse.ArgumentParser(); p.add_argument('--python',type=Path,required=True); p.add_argument('--project-root',type=Path,required=True); p.add_argument('--metadata',type=Path,required=True); p.add_argument('--expected-count',type=int,required=True); p.add_argument('--timeout',type=int,default=180); a=p.parse_args()
    if not a.python.is_file(): raise RuntimeError(f'MCP_RUNTIME_PYTHON_MISSING={a.python}')
    if not a.project_root.is_dir(): raise RuntimeError(f'MCP_PROJECT_ROOT_MISSING={a.project_root}')
    if not a.metadata.is_file(): raise RuntimeError(f'REUSABLE_ASSET_METADATA_MISSING={a.metadata}')
    asyncio.run(run(a.python.resolve(),a.project_root.resolve(),a.metadata.resolve(),a.expected_count,a.timeout)); return 0
if __name__=='__main__': raise SystemExit(main())
