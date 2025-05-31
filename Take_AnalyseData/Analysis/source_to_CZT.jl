for hor in 0:0.5:12
    HorAbsMM(hor, motor)
    h = round(PosHor(motor), digits = 1)
    v = round(PosVert(motor), digits = 1)
    take_czt_data(cam01, cam02, 300, "R_$(h)mm_Z_$(v)mm")
end
HorAbsMM(200,motor)
