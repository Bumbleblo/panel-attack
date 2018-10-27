------
--- Module with IO functions for save game state
--- Write data in files and handle exception in IO operations
-- @module server_file_io 
------

--- Check if is really a file
-- @function check_is_file
-- @param name string with name of the file
-- return boolean, true if is a file, else if not.
function check_is_file(name) 
    if not check_is_dir(name) then
        return assert(os.rename(name,name)) 
        -- note that the short evaluation is to
        -- return false instead of a possible nil
    else
        return false
    end
end

--- Check if is a directory
-- @function check_is_file_dir
-- @param name name of the file
-- @return boolean, true if is a directory, false if is not.
function check_is_file_dir(name) 
    if type(name)~='string' then 
        return false 
    else
        return assert((os.rename(name, name)))  
    end
end

--- Check if is a directory (most accurately than check_is_file)
-- @function check_is_dir
-- @param name string with name of the file
-- @return boolean, true if is a directory, false if not.
function check_is_dir(name) 
    if type(name)~='string' then 
        return false 
    else
        local lfs = require('lfs')
        local current_dir = lfs.currentdir() 
        local is_dir = lfs.chdir(name)  

        lfs.chdir(current_dir)

        return assert(is_dir) 
    end
end

--- Create a directory using path
-- @function make_dir 
-- @param path string with path of the new directory
-- @return nil
function make_dir(path) 
    assert(path) 

    local sep, pStr = package.config:sub(1, 1), ''

    for dir in path:gmatch('[^' .. sep .. ']+') do
        pStr = pStr .. dir .. sep
        lfs.mkdir(pStr)
    end
end

--- Write text in player files
-- @function write_playters_file
-- @param nil
-- @return nil
function write_players_file() 
    -- handle exceptions with IO operations
    local function write_file()
        local file = assert(io.open('players.txt', 'w')) 

        io.output(file)
        io.write(json.encode(playerbase.players))
        io.close(file)
    end

    pcall(write_file) 
end

--- Read data of the players file
-- @function read_players_file
-- @param nil
-- return nil
function read_players_file() 
    local function read_file() 
        local file = assert(io.open('players.txt', 'r')) 

        assert(io.input(file), "input is invalid") 
        playerbase.players = json.decode(io.read('*all'))
        io.close(file)
    end 

    pcall(read_file)
end

--- Write data in file deleted_players.txt 
-- @function write_deleted_players_file
-- @param nil
-- @return nil
function write_deleted_players_file() 
    -- Handle IO operation
    local function write_file()
        local file = assert(io.open('deleted_players.txt', 'w')) 

        io.output(file)
        io.write(json.encode(playerbase.players))
        io.close(file)
    end 

    pcall(write_file)
end

--- Read data of deleted players 
-- @function read_deletd_players_file
-- @param nil
-- @return nil
function read_deleted_players_file() 
    local function read_file()
        local file = assert(io.open('deleted_players.txt', 'r'))

        assert(io.input(file), "input is invalid") 
        playerbase.deleted_players = json.decode(io.read('*all'))
        io.close(file)
    end

    pcall(read_file)
end

--- Save data in leaderboard
-- @function write_leaderboard_file
-- @param nil
-- @param nil
function write_leaderboard_file() 
    local function write_file()
        local file = assert(io.open('leaderboard.txt', 'w'))  

        io.output(file)
        io.write(json.encode(leaderboard.players))
        io.close(file)
    end

    pcall(write_file())
end

--- Read leaderboard 
-- @function read_leaderboard_file
-- @param nil
-- @param nil
function read_leaderboard_file() 
    local function read_file()
        local file = assert(io.open('leaderboard.txt', 'r')) 

        assert(io.input(file), "input is invalid") 
        leaderboard.players = json.decode(io.read('*all'))
        io.close(file)
    end 
    
    pcall(read_file)
end

--- Save replay
-- @function write_replay_file
-- @param replay Stack of the moves
-- @param path of file
-- @param filename string with name of the file
-- @return nil
function write_replay_file(replay, path, filename) 
    assert(replay)
    assert(path)  
    assert(filename) 
    
    local function write_file()
        make_dir(path)
        local file = assert(io.open(path..'/'..filename, 'w')) 

        io.output(file)
        io.write(json.encode(replay))
        io.close(file)
    end 

    pcall(write_file)
end
--- User csprng to generate random issues
-- @function read_csprng_seed_file
-- @param nil
-- @return nil
function read_csprng_seed_file()
    local function read_file()
        local file = assert(io.open('csprng_seed.txt', 'r') ) 

        if file then
            assert(io.input(file), "input is invalid") 
            csprng_seed = io.read('*all') 
            io.close(file)
        else
            print('csprng_seed.txt could not be read.  Writing a new ' .. 
                'default (2000) csprng_seed.txt')

            local new_file = assert(io.open('csprng_seed.txt', 'w')) 

            io.output(new_file)
            io.write('2000')
            io.close(new_file)
            csprng_seed = '2000'
        end

        if tonumber(csprng_seed) then
            local temporary = assert(tonumber(csprng_seed)) 

            csprng_seed = temporary
        else 
            print('ERROR: csprng_seed.txt content is not numeric. ' .. 
                'Using default (2000) as csprng_seed')

            csprng_seed = 2000
        end
    end 

    pcall(read_file)
end
