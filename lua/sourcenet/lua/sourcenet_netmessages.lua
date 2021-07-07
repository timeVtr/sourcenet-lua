--require("sourcenet")

-- Debug ConVar
local sourcenet_netmessage_info = CreateConVar("sourcenet_netmessage_info", "0")

local function log2(val)
	return math.ceil(math.log(val) / math.log(2))
end

-- Engine definitions
NET_MESSAGE_BITS = 6
NUM_NEW_COMMAND_BITS = 4
NUM_BACKUP_COMMAND_BITS = 3
MAX_TABLES_BITS = log2(32)
MAX_USERMESSAGE_BITS = 11
MAX_ENTITYMESSAGE_BITS = 11
MAX_SERVER_CLASS_BITS = 9
MAX_EDICT_BITS = 13

function SourceNetMsg(msg)
	if sourcenet_netmessage_info:GetInt() ~= 0 then
		Msg("[snmi] " .. msg)
	end
end

-- add limits here for the netmessages we want (just svc_VoiceData for now)
SOURCENET_LIMITS = SOURCENET_LIMITS or {}
local LIMITS = SOURCENET_LIMITS
LIMITS[svc_VoiceData] = {}
local time = SysTime

NET_MESSAGES = {
	[net_NOP] = { -- 0
		DefaultCopy = function(netchan, read, write)
			write:WriteUInt(net_NOP, NET_MESSAGE_BITS)
		end
	},

	[net_Disconnect] = { -- 1
		DefaultCopy = function(netchan, read, write)
			write:WriteUInt(net_Disconnect, NET_MESSAGE_BITS)

			local reason = read:ReadString()
			write:WriteString(reason)

			SourceNetMsg(string.format("net_Disconnect %s\n", reason))
		end
	},

	[net_File] = { -- 2
		DefaultCopy = function(netchan, read, write)
			write:WriteUInt(net_File, NET_MESSAGE_BITS)

			local transferid = read:ReadUInt(32)
			write:WriteUInt(transferid, 32)

			local requested = read:ReadBit()
			write:WriteBit(requested)

			if requested == 0 then
				SourceNetMsg(string.format("net_File %i,false\n", transferid))
				return
			end

			local requesttype = read:ReadUInt(1)
			write:WriteUInt(requesttype, 1)

			local fileid = read:ReadUInt(32)
			write:WriteUInt(fileid, 32)

			SourceNetMsg(string.format("net_File %i,true,%i,%i\n", transferid, requesttype, fileid))
		end
	},

	[net_Tick] = { -- 3
		DefaultCopy = function(netchan, read, write)
			write:WriteUInt(net_Tick, NET_MESSAGE_BITS)

			local tick = read:ReadLong()
			write:WriteLong(tick)

			local hostframetime = read:ReadUInt(16)
			write:WriteUInt(hostframetime, 16)

			local hostframetimedeviation = read:ReadUInt(16)
			write:WriteUInt(hostframetimedeviation, 16)

			--SourceNetMsg(string.format("net_Tick %i,%i,%i\n", tick, hostframetime, hostframetimedeviation))
		end
	},

	[net_StringCmd] = { -- 4
		DefaultCopy = function(netchan, read, write)
			write:WriteUInt(net_StringCmd, NET_MESSAGE_BITS)

			local cmd = read:ReadString()
			write:WriteString(cmd)

			SourceNetMsg(string.format("net_StringCmd %s\n", cmd))
		end
	},


	[net_SignonState] = { -- 6
		DefaultCopy = function(netchan, read, write)
			write:WriteUInt(net_SignonState, NET_MESSAGE_BITS)

			local state = read:ReadByte()
			write:WriteByte(state)

			local servercount = read:ReadLong()
			write:WriteLong(servercount)

			SourceNetMsg(string.format("net_SignonState %i,%i\n", state, servercount))
		end
	},

	CLC = {

		[clc_VoiceData] = { -- 10
			DefaultCopy = function(netchan, read, write)
				write:WriteUInt(clc_VoiceData, NET_MESSAGE_BITS)

				local bits = read:ReadWord()
				write:WriteWord(bits)

				if bits > 0 then
					local data = read:ReadBits(bits)
					write:WriteBits(data)
				end

				SourceNetMsg(string.format("clc_VoiceData %i\n", bits))
			end
		},
	},

	SVC = {
		[svc_VoiceInit] = { -- 14
			DefaultCopy = function(netchan, read, write)
				write:WriteUInt(svc_VoiceInit, NET_MESSAGE_BITS)

				local codec = read:ReadString()
				write:WriteString(codec)

				local quality = read:ReadByte()
				write:WriteByte(quality)

				SourceNetMsg(string.format("svc_VoiceInit codec=%s,quality=%i\n", codec, quality))
			end
		},

		[svc_VoiceData] = { -- 15
			DefaultCopy = function(netchan, read, write)
				write:WriteUInt(svc_VoiceData, NET_MESSAGE_BITS)

				local client = read:ReadByte()
				write:WriteByte(client)

				local proximity = read:ReadByte()
				write:WriteByte(proximity)

				local bits = read:ReadWord()
				write:WriteWord(bits)

				if bits > 0 then
					local voicedata = read:ReadBits(bits)
					write:WriteBits(voicedata)
				else
					
					local ply = ents.GetByIndex(client + 1)
					
					local LIMITS = LIMITS[svc_VoiceData]
					local limit = LIMITS[ply]
					local now = time()

					if not limit then
						limit = {
							lasttime = now,
							firsttime = now,
							calls = 1,
							banned = false
						}
						LIMITS[ply] = limit
					elseif now > limit.firsttime + 2 then
						limit.firsttime = now
						limit.lasttime = now
						limit.calls = 1
					elseif limit.lasttime + 0.1 > now then
						if limit.calls < 200 then
							limit.calls = limit.calls + 1
							limit.lasttime = now		
						else
							-- save player's steam id
							local crasher_steamid = ply:SteamID()
							
							-- immediately disconnect player from the server
							ply:Kick("no pls")
							
							-- ban player's steamid here if you wish
							if not limit.banned and D3A.Bans.BanPlayer(crasher_steamid, "CONSOLE", 600, "year", "Server Crasher Exploit | Appeal your ban at GarnetGaming.net.") then
								limit.banned = true
								D3A.Chat.Broadcast(crasher_steamid .. " was banned permanently by Console Reason: Server Crasher Exploit | Appeal your ban at GarnetGaming.net.")
								CHTTP({
									method = "POST",
									url = "https://discordapp.com/api/webhooks/858532494873067530/DtwlSVl1VdYaufxjfSa5KN0pBgpZu8yFEDpMb52otgTUF4mfv_9IXdGlekCDHMeHylQg",
									body = util.TableToJSON({["content"] = "[MURDER]: " .. crasher_steamid .. " was banned permanently by Console Reason: Server Crasher Exploit"}),
									type = "application/json"
								  }
								)
							end
						end
					else
						limit.calls = 1
						limit.lasttime = now
					end
				end
				SourceNetMsg(string.format("svc_VoiceData client=%i,proximity=%i,bits=%i\n", client, proximity, bits))
			end
		},
	}
}