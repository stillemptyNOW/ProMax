from fastapi import HTTPException, Request


async def read_bounded_body(request: Request, max_bytes: int) -> bytearray:
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > max_bytes:
            raise HTTPException(413, "body_too_large")
        body.extend(chunk)
    return body
