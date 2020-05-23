;TSR программа
;блокирует или деблокирует по нажатию F10 доступ к файлу
;имя файла задается при запуске программы
;удаление происходит идентично установке

code_seg                segment
                        assume  CS:code_seg,DS:code_seg,SS:code_seg
                        org     0100h 			;смещение под служебную информацию, пропускаем 256 байт для MS-DOS

;УПРАВЛЯЮЩАЯ ЛОГИКА

start:                  
	jmp     start_installer                     ;запуск установщика

;ВСПОМОГАТЕЛЬНЫЕ ПРОЦЕДУРЫ

;ОБРАБОТЧИК ПРЕРЫВАНИЯ INT 09h

int_09h_handler proc near                       ;обрабатывает прерывание 09h
    
    push    ES
    push    DS                                  ;установливаем регистр DS
    push    CS
    pop     DS
    cmp     is_passthrough, 01h
    je      pass_09h_through
    push    AX                                  ;пушим регистр AX чтобы сохранить его
    in      AL, 60h                             ;получаем код нажатой клавиши
    cmp     AL, 44h                             ;проверяем, нажата ли клавиша F10
    pop     AX                                  ;достаем регистр AX
    jne     pass_09h_through
    push    AX                                  ;помещаем регистры в стек, чтобы сохранить их
    push    BX
    push    CX
    push    DX
    push    SI
    push    DI
    mov     AL, is_file_locked
    cmp     AL, 00h                             ;проверяем, заблокирован ли файл
    je      lock_file                           ;блокируем файл
    jmp     unlock_file                         ;деблокируем файл

	lock_file:              
		mov     AX, 5C00h                           ;устанавливаем функцию DOS для блокировки файла
		mov     BX, file_handler                    ;установливаем файл для блокировки
		mov     CX, 0000h                           ;заблокируем файл с позиции 0
		mov     DX, 0000h
		mov     SI, 00007FFFh                       ;до конца
		mov     DI, 00007FFFh
		int     21h                                 ;вызываем функцию блокировки
		mov     is_file_locked, 01h                 ;устанавливаем флаг
		jmp     restore_registers
	
	unlock_file:            
		mov     AX, 5C01h							;устанавливаем функцию DOS для деблокировки файла
		mov     BX, file_handler                    ;установливаем файл для деблокировки
		mov     CX, 0000h                           ;деблокируем файл с позиции 0
		mov     DX, 0000h
		mov     SI, 00007FFFh                       ;до конца
		mov     DI, 00007FFFh
		int     21h                                 ;вызываем функцию разблокировки
		mov     is_file_locked, 00h                 ;чистим флаг

	restore_registers:      
		pop     DI                                  ;восстанавливаем регистры
		pop     SI
		pop     DX
		pop     CX
		pop     BX
		pop     AX
		
	pass_09h_through:       
		pop     DS                                  ;восстанавливаем регистр DS
		pop     ES
		jmp     dword ptr CS:[old_09h_handler]      ;вызываем старый обработчик 09h

int_09h_handler endp

;ОБРАБОТЧИК ПРЕРЫВАНИЯ INT 21h

int_21h_handler  proc near                      ;обрабатывает прерывание 21h
    
    push    ES
    push    DS                                  ;установливаем регистр DS
    push    CS
    pop     DS
    cmp     AH, 3Ch                             ;проверяем открыт ли файл
    jl      pass_21h_through
    cmp     AH, 3Dh
    jg      pass_21h_through
    cmp     is_file_locked, 00h                 ;проверяем залочен ли файл
    je      pass_21h_through
    pop     DS                                  ;восстанавливаем регистр DS
    push    DS                                  ;и сохраняем его снова
    push    AX									;помещаем регистры в стек, чтобы сохранить их
    push    BX
    push    CX
    push    DX
    push    SI
    push    DI                                  
    push    DS
    pop     CX                                  ;установливаем исходный сегмент
    mov     SI, DX                              ;установливаем смещение источника
    push    CS
    pop     DX                                  ;установливаем целевой сегмент
    push    CS
    pop     DS
    mov     DI, offset file_name                ;установливаем целевой смещение
    call    compare_strings
    cmp     AL, 00h                             ;проверяем, не совпадают ли имена файлов
    pop     DI
    pop     SI
    pop     DX
    pop     CX
    pop     BX
    pop     AX                                  ;восстанавливаем регистры
    je      pass_21h_through
    pop     DS                                  ;восстанавливаем регистр DS
    pop     ES
    popf
    stc                                         ;установливаем флаг переноса
    pushf
    mov     AX, 0000h                           ;устанавливаем код ошибки
    iret

	pass_21h_through:       
		pop     DS                                  ;восстанавливаем регистр DS
        	pop     ES
        	jmp     dword ptr CS:[old_21h_handler]      ;вызываем старый обработчик 21h

int_21h_handler endp

;ОБРАБОТЧИК ПРЕРЫВАНИЯ INT 2Fh

int_2Fh_handler proc near                       ;обрабатывает прерывание 2Fh
    
    push    ES
    push    DS                                  ;установливаем регистр DS
    push    CS
    pop     DS
    cmp     is_passthrough, 01h
    je      pass_2Fh_through
    cmp     AX, 8000h                           ;проверяем, установлена ли программа
    je      installation_check
    cmp     AX, 8001h                           ;удаляем программу
    je      uninstallation
    cmp     AX, 8002h                           ;проверяем залочен ли файл
    je      lock_check
    jmp     pass_2Fh_through
	
	installation_check:     
		mov     AL, 00FFh                           ;установите FFh в регистр AL, чтобы отметить программу как уже загруженную
		pop     DS                                  ;восстанавливаем регистр DS
		pop     ES
		iret                                        ;прерываем прерывание
	
	uninstallation:         
		push    AX                                  ;помещаем регистры в стек, чтобы сохранить их
		push    BX
		push    CX
		push    DX
		push    SI
		push    DI
		cmp     is_file_locked, 01h
		jne     skip_file_unlocking
		mov     AX, 5C01h
		mov     BX, file_handler                    ;установливаем файл для деблокировки
		mov     CX, 0000h                           ;деблокируем файл с позиции 0
		mov     DX, 0000h
		mov     SI, 0000FFFFh                       ;до конца
		mov     DI, 0000FFFFh
		int     21h                                 ;вызываем функцию разблокировки
	
	skip_file_unlocking:    
		mov     AH, 3Eh
		mov     BX, file_handler
		int     21h                         	    ;закрываем файл
		mov     AX, 3509h
		int     21h                                 ;получаем адрес прерывания 09h
		cmp     BX, offset int_09h_handler          ;сравниваем смещение int_09h_handler
		jne     make_passthrough
		mov     CX, CS
		mov     DX, ES
		cmp     CX, DX                              ;сравниваем сегмент int_09h_handler
		jne     make_passthrough
		mov     AX, 3521h
		int     21h                                 ;получаем адрес прерывания 21h
		cmp     BX, offset int_21h_handler          ;сравниваем смещение int_21h_handler
		jne     make_passthrough
		mov     CX, CS
		mov     DX, ES
		cmp     CX, DX                              ;сравниваем сегмент int_21h_handler
		jne     make_passthrough
		mov     AX, 352Fh
		int     21h                                 ;получаем адрес прерывания 2Fh 
		cmp     BX, offset int_2Fh_handler          ;сравниваем смещение int_2Fh_handler
		jne     make_passthrough
		mov     CX, CS
		mov     DX, ES
		cmp     CX, DX                              ;сравниваем сегмент int_2Fh_handler
		jne     make_passthrough
		push    DS
		mov     AX, 2509h
		mov     DX, word ptr old_09h_handler
		mov     DS, word ptr old_09h_handler + 2
		int     21h                                 ;восстановливаем адрес прерывания 09h
		pop     DS
		push    DS
		mov     AX, 2521h
		mov     DX, word ptr old_21h_handler
		mov     DS, word ptr old_21h_handler + 2
		int     21h                                 ;восстановливаем адрес прерывания 21h
		pop     DS
		push    DS
		mov     AX, 252Fh
		mov     DX, word ptr old_2Fh_handler
		mov     DS, word ptr old_2Fh_handler + 2
		int     21h                                 ;восстановливаем адрес прерывания 2Fh
		pop     DS									
		pop     DI                                  ;восстанавливаем регистры
		pop     SI
		pop     DX
		pop     CX
		pop     BX
		pop     AX
		mov     AL, 01h                             ;установливаем 01h в регистр AL, чтобы пометить программу как удаленную
		pop     DS
		pop     ES
		iret
	
	make_passthrough:       
		mov     is_passthrough, 01h                 ;устанавливаем флаг сквозного режима
		mov     AL, 00h                             ;установливаем 00h в регистр AL, чтобы пометить программу как сквозную
		pop     DS                                  ;восстанавливаем регистр DS
		pop     ES
		iret                                        ;прерываем прерывание
	
	lock_check:             
		mov     AL, is_file_locked                  ;установливаем регистр AL, чтобы пометить файл как заблокированный
		pop     DS                                  ;восстанавливаем регистр DS
		pop     ES
		iret                                        ;прерываем прерывание
	
	pass_2Fh_through:       
		pop     DS                                  ;восстанавливаем регистр DS
		pop     ES
		jmp     dword ptr CS:[old_2Fh_handler]      ;вызываем старый обработчик 2Аh

int_2Fh_handler endp

;СРАВНЕНИЕ СТРОК

compare_strings proc near                           ;сравнивает две строки из CX: SI и DX: DI, устанавливает регистр AL в 1,
													;если они равны, в противном случае устанавливает его в 0
	push    DS
	
	compare_next_char:      
		push    CX
		pop     DS                                  ;установливаем исходный сегмент
		mov     BH, DS:[SI]                         ;копируем первый символ
		push    DX
		pop     DS                                  ;установливаем регистр назначения
		mov     BL, DS:[DI]                         ;копируем второй символ
		inc     SI
		inc     DI                                  ;переходим к следующему символу
		cmp     BH, BL                              ;проверяем, равны ли символы
		jne     strings_are_not_equal               
		cmp     BH, 00h                             ;проверяем, был ли достигнут конец строки
		je      strings_are_equal
		jmp     compare_next_char
	
	strings_are_equal:      
		mov     AL, 01h
		pop     DS
		ret

	strings_are_not_equal:  
		mov     AL, 00h
        	pop     DS
        	ret
		
compare_strings endp

;КОНСТАНТЫ

is_passthrough          db      00h
is_file_locked          db      00h
file_name               db      0080h dup(00h)
file_handler            dw      0000h
old_09h_handler         dd      00000000h
old_21h_handler         dd      00000000h
old_2Fh_handler         dd      00000000h

;УПРАВЛЯЮЩАЯ ЛОГИКА

start_installer:        
    call    check_if_installed
    cmp     AL, 00FFh                           ;проверяем, установлена ли программа
    jne     program_not_installed
    jmp     program_installed

program_not_installed:  
    call    install_program
    int     20h

program_installed:      
	call    uninstall_program
	int     20h

;ВСПОМОГАТЕЛЬНЫЕ ПРОЦЕДУРЫ

;ЧТЕНИЕ ИМЕНИ ФАЙЛА ДЛЯ БЛОКИРОВКИ

read_file_name proc near                            ;пытаемся прочитать имя файла из префикса сегмента программы, если неудачно, читаем его из консоли
    
    mov     CL, DS:[80h]
    cmp     CL, 00h                             	;проверяет, пуст ли буфер аргументов в префиксе сегмента программы
    je      read_from_console
    dec     CL                                  	;уменьшить регистр CL, чтобы не копировать \r
    mov     SI, 82h                             	;устанавливаем регистр индекса источника на первый символ в префиксе сегмента программы
    mov     DI, offset file_name                	;установить регистр индекса назначения на первый символ в массиве file_name 

	copy_next_char_psp:		
		mov		AL, DS:[SI]
		mov     byte ptr[DI], AL                    ;копируем символ из префикса сегмента программы в массив file_name
		inc     SI                                  ;переходим к следующему символу в префиксе сегмента программы
		inc     DI                                  ;перейти к следующему символу в массиве file_name
		dec     CL
		cmp     CL, 00h                             ;проверяем, был ли последний символ скопирован из префикса сегмента программы в массив file_name
		jg      copy_next_char_psp
		mov     AL, 00h
		mov     byte ptr[DI], AL                    ;записываем нулевой символ для использования массива file_name в качестве имени файла
		ret
	
	read_from_console:      
		mov     DX, offset request_string
		mov     AH, 09h
		int     21h                                 ;печатаем строку вопроса для пользователя, чтобы узнать имя файла
		mov     DI, offset file_name
		mov     byte ptr[DI], 80h                   ;записываем длину массива file_name в первый байт
		mov     DX, offset file_name
		mov     AH, 0Ah
		int     21h                                 ;прочитаем строку из консоли в массив file_name
		mov     CL, file_name[01h]                  ;скопируем длину строки в регистр CL
		mov     SI, offset file_name + 2h           ;установливаем регистр индекса источника на первый символ строки
		mov     DI, offset file_name                ;установливаем регистр индекса назначения на первый символ в массиве file_name

	copy_next_char_console: 
		mov     AL, DS:[SI]
		mov     byte ptr[DI], AL                    ;скопируем символ из строки в массив file_name
		inc     SI                                  ;перейти к следующему символу строки
		inc     DI                                  ;перейти к следующему символу в массиве file_name
		dec     CL
		cmp     CL, 00h                             ;проверяем, был ли последний символ скопирован из строки в массив file_name
		jg      copy_next_char_console
		mov     AL, 00h
		mov     byte ptr[DI], AL                    ;записываем нулевой символ для использования массива file_name в качестве имени файла
		mov     AH, 02h
		mov     DL, 0Dh
		int     21h                                 ;печатаем \r
		mov     DL, 0Ah
		int     21h                                 ;печатаем \n
		ret
		
read_file_name endp

;ПРОВЕРКА НА УСТАНОВКУ

check_if_installed proc near                    ;проверяет, установлена ли программа, результат сохраняет в регистре AL
    
    mov     AX, 8000h                           ;подготавливаем регистр AX перед вызовом прерывания 2Fh
    int     2Fh                                 ;проверяем, установлена ли программа
    ret
	
check_if_installed endp

;ПРОВЕРКА НА ЗАЛОЧЕННОСТЬ ФАЙЛА

check_if_locked proc near                       ;проверяет, заблокирован ли файл, результат сохраняет в регистре AL
    
	mov     AX, 8002h
    	int     2Fh                                 ;проверяем файл на залоченность
    	ret
	
check_if_locked endp

;ДИАЛОГ УСТАНОВКИ ПРОГРАММЫ

install_program proc near                       ;устанавливает программу по запросу
                        
    mov     AH, 09h
    mov     DX, offset install_string
    int     21h                                 ;печатаем вопрос
    mov     AH, 08h
    int     21h                                 ;получаем нажатую пользователем клавишу
    cmp     AL, 79h                             ;проверяем, является ли символ клавишей 'y'
    jne     do_not_install
    call    read_file_name                      ;получаем имя файла
    mov     AX, 3D02h
    mov     DX, offset file_name
    int     21h                                 ;открываем файл, который будет заблокирован
    jc      unable_to_open
    mov     file_handler, AX                    ;копируем обработчик файла из регистра AX в переменную
    mov     AX, 3509h
    int     21h                                 ;получаем адрес прерывания 09h
    mov     word ptr old_09h_handler, BX
    mov     word ptr old_09h_handler + 2, ES
    mov     AX, 3521h
    int     21h                                 ;получаем адрес прерывания 21h
    mov     word ptr old_21h_handler, BX
    mov     word ptr old_21h_handler + 2, ES
    mov     AX, 352Fh
    int     21h                                 ;получаем адрес прерывания 2Fh
    mov     word ptr old_2Fh_handler, BX
    mov     word ptr old_2Fh_handler + 2, ES
    cli										    ;чистим флаг прерывания
    mov     AX, 2509h
    mov     DX, offset int_09h_handler
    int     21h                                 ;устанавливаем адрес прерывания 09h
    mov     AX, 2521h
    mov     DX, offset int_21h_handler
    int     21h                                 ;устанавливаем адрес прерывания 21h
    mov     AX, 252Fh
    mov     DX, offset int_2Fh_handler
    int     21h                                 ;устанавливаем адрес прерывания 2Fh
    sti										    ;устанавливаем флаг прерывания
    mov     AH, 09h
    mov     DX, offset install_suc_string
    int     21h                                 ;распечатать сообщение
    mov     DX, offset start_installer
    int     27h                                 ;вернуть контроль и стать резидентной
	
	unable_to_open:         
		mov     AH, 09h
		mov     DX, offset install_unsuc_string
		int     21h                                 ;распечатать ошибку
	do_not_install:         
		ret
	
install_program endp

;ДИАЛОГ УДАЛЕНИЯ ПРОГРАММЫ

uninstall_program proc near                         ;удаляем программу по запросу
    
    call    check_if_locked
    cmp     AL, 0000h                           	;проверяем, разблокирован ли файл в данный момент
    je      file_unlocked
    jmp     file_locked
	
	file_locked:            
		mov     AH, 09h
		mov     DX, offset file_locked_string
		int     21h                                 ;печатаем сообщение
		jmp     ask_to_uninstall

	file_unlocked:          
		mov     AH, 09h
		mov     DX, offset file_unlocked_string
		int     21h                                 ;печатаем сообщение

	ask_to_uninstall:       
		mov     DX, offset uninstall_string
		int     21h                                 ;печатаем вопрос
		mov     AH, 08h
		int     21h                                 ;получаем символ нажатый пользователем
		cmp     AL, 79h                             ;проверяем, является ли символ клавишей 'y'
		jne     do_not_uninstall
		mov     AX, 8001h
		int     2Fh
		cmp     AL, 01h                             ;проверяем, была ли программа удалена или нет
		je      was_uninstalled
		mov     AH, 09h
		mov     DX, offset uninstall_pass_string
		int     21h                                 ;пишем предупреждение
        	ret

	was_uninstalled:        
		mov     AH, 09h
		mov     DX, offset uninstall_suc_string
		int     21h                                 ;печатаем сообщение
	
	do_not_uninstall:       
		ret

uninstall_program endp

;СТРОКИ

request_string          db      'Enter a file name:', 0Dh, 0Ah, 24h
install_string          db      'The program was not installed yet. Do you want to install it? (y/n)', 0Dh, 0Ah, 24h
install_suc_string      db      'The program was installed successfully.', 24h
install_unsuc_string    db      'The program was unable to open the file.', 24h
file_locked_string      db      'The file is currently locked.', 0Dh, 0Ah, 24h
file_unlocked_string    db      'The file is currently unlocked.', 0Dh, 0Ah, 24h
uninstall_string        db      'The program was already installed. Do you want to uninstall it? (y/n)', 0Dh, 0Ah, 24h
uninstall_suc_string    db      'The program was uninstalled successfully.', 24h
uninstall_pass_string   db      'The program was not uninstalled successfully. It was switched to the passthrough mode.', 24h

code_seg                ends
                        end     start
